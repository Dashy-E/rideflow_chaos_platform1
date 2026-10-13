"""Fault backends.

KubernetesBackend talks to a real cluster via the official client (this is
what runs when deployed to EKS, per doc §8.4 RBAC spec).

LocalBackend drives the same fault catalogue against the docker-compose dev
stack with no Kubernetes control plane at all — it flips each service's
`/admin/chaos` runtime switch (added specifically for this) over HTTP, and
uses the Docker Engine API for pod-kill-equivalent container restarts. This
is what makes the whole chaos story demoable on a laptop with nothing but
`docker compose up`.
"""
import logging
import os
import random

import httpx

logger = logging.getLogger("chaos.backends")

SERVICE_URLS = {
    "api-gateway": os.getenv("API_GATEWAY_URL", "http://api-gateway:8080"),
    "user-service": os.getenv("USER_SERVICE_URL", "http://user-service:8081"),
    "ride-service": os.getenv("RIDE_SERVICE_URL", "http://ride-service:8082"),
    "driver-service": os.getenv("DRIVER_SERVICE_URL", "http://driver-service:8083"),
    "pricing-service": os.getenv("PRICING_SERVICE_URL", "http://pricing-service:8084"),
}


def target_service_from_selector(label_selector: str | None) -> str:
    """labelSelector is `app=<service-name>` per doc's YAML schema."""
    if not label_selector or "=" not in label_selector:
        raise ValueError(f"expected labelSelector like 'app=ride-service', got {label_selector!r}")
    _, value = label_selector.split("=", 1)
    return value.strip()


class FaultBackend:
    async def pod_kill(self, service: str, count: int) -> str:
        raise NotImplementedError

    async def revert_pod_kill(self, service: str) -> str:
        return "no explicit revert needed — ReplicaSet/kubelet already restored the pod"

    async def cpu_hog(self, service: str, duration_s: int) -> str:
        raise NotImplementedError

    async def revert_cpu_hog(self, service: str) -> str:
        return "busy-loop self-terminates via timeout"

    async def oom(self, service: str) -> str:
        raise NotImplementedError

    async def dependency_failure(self, service: str) -> str:
        raise NotImplementedError

    async def revert_dependency_failure(self, service: str) -> str:
        raise NotImplementedError

    async def network_latency(self, service: str, ms: int) -> str:
        raise NotImplementedError

    async def packet_loss(self, service: str, percent: int) -> str:
        raise NotImplementedError

    async def revert_network_fault(self, service: str) -> str:
        raise NotImplementedError

    async def az_blackhole(self, zone: str) -> str:
        raise NotImplementedError

    async def revert_az_blackhole(self, zone: str) -> str:
        raise NotImplementedError

    async def region_failure(self) -> str:
        raise NotImplementedError

    async def revert_region_failure(self) -> str:
        raise NotImplementedError


class LocalBackend(FaultBackend):
    """Drives the docker-compose stack. Blast-radius-safe by construction:
    it never touches more than the one targeted service."""

    def __init__(self):
        self._client = httpx.AsyncClient(timeout=5.0)
        try:
            import docker  # type: ignore
            self._docker = docker.from_env()
        except Exception as e:
            logger.warning("docker SDK unavailable (%s) — pod_kill/oom will be simulated via /admin/chaos instead", e)
            self._docker = None

    async def _set_chaos(self, service: str, mode: str) -> str:
        url = f"{SERVICE_URLS[service]}/admin/chaos"
        r = await self._client.patch(url, params={"mode": mode})
        r.raise_for_status()
        return f"set {service} runtime fault mode={mode!r}"

    async def pod_kill(self, service: str, count: int) -> str:
        if self._docker:
            containers = [c for c in self._docker.containers.list() if service in c.name]
            if not containers:
                raise RuntimeError(f"no running container found for {service}")
            victim = random.choice(containers)
            victim.restart(timeout=0)
            return f"docker restart {victim.name} (compose will not resurrect it as a new pod, but the process restarts, mirroring ReplicaSet recovery)"
        return await self._set_chaos(service, "error")

    async def revert_pod_kill(self, service: str) -> str:
        if self._docker:
            return await super().revert_pod_kill(service)
        # the no-docker fallback above left the service in "error" mode, which
        # nothing restarts its way out of — clear it explicitly
        return await self._set_chaos(service, "")

    async def cpu_hog(self, service: str, duration_s: int) -> str:
        return await self._set_chaos(service, "latency")  # closest local proxy: saturate via induced latency

    async def revert_cpu_hog(self, service: str) -> str:
        # unlike the real busy-loop, the latency proxy has no timeout of its
        # own; without this the service stayed slow after every cpu_hog run
        return await self._set_chaos(service, "")

    async def oom(self, service: str) -> str:
        return await self.pod_kill(service, 1)

    async def dependency_failure(self, service: str) -> str:
        return await self._set_chaos(service, "error")

    async def revert_dependency_failure(self, service: str) -> str:
        return await self._set_chaos(service, "")

    async def network_latency(self, service: str, ms: int) -> str:
        return await self._set_chaos(service, "latency")

    async def packet_loss(self, service: str, percent: int) -> str:
        return await self._set_chaos(service, "error")

    async def revert_network_fault(self, service: str) -> str:
        return await self._set_chaos(service, "")

    async def az_blackhole(self, zone: str) -> str:
        return "az_blackhole is not meaningful in single-host docker-compose — no-op (use the kubernetes backend against kind/EKS)"

    async def revert_az_blackhole(self, zone: str) -> str:
        return "no-op"

    async def region_failure(self) -> str:
        r = await self._client.post(f"{SERVICE_URLS['api-gateway']}/admin/region", params={"state": "unhealthy"})
        r.raise_for_status()
        return "set api-gateway /healthz/region to unhealthy"

    async def revert_region_failure(self) -> str:
        r = await self._client.post(f"{SERVICE_URLS['api-gateway']}/admin/region", params={"state": "healthy"})
        r.raise_for_status()
        return "restored api-gateway /healthz/region to healthy"


class KubernetesBackend(FaultBackend):
    """Talks to a real cluster. Requires the RBAC in doc §8.4 (namespace-
    scoped Role for pods/deployments + a narrow ClusterRole for node cordon).
    """

    def __init__(self, namespace: str = "rideflow"):
        from kubernetes import client, config
        try:
            config.load_incluster_config()
        except Exception:
            config.load_kube_config()
        self.v1 = client.CoreV1Api()
        self.apps = client.AppsV1Api()
        self.namespace = namespace

    async def pod_kill(self, service: str, count: int) -> str:
        pods = self.v1.list_namespaced_pod(self.namespace, label_selector=f"app={service}").items
        ready = [p for p in pods if p.status.phase == "Running"]
        if len(ready) <= 1:
            raise RuntimeError("blast radius guard: refusing to kill the last replica")
        victims = random.sample(ready, min(count, len(ready) - 1))
        for v in victims:
            self.v1.delete_namespaced_pod(v.metadata.name, self.namespace, grace_period_seconds=0)
        return f"deleted pods: {[v.metadata.name for v in victims]}"

    async def cpu_hog(self, service: str, duration_s: int) -> str:
        from kubernetes.stream import stream
        pods = self.v1.list_namespaced_pod(self.namespace, label_selector=f"app={service}").items
        if not pods:
            raise RuntimeError(f"no pods for {service}")
        target = pods[0].metadata.name
        cmd = ["/bin/sh", "-c", f"timeout {duration_s} sh -c 'while true; do :; done' &"]
        stream(self.v1.connect_get_namespaced_pod_exec, target, self.namespace,
               command=cmd, stderr=True, stdin=False, stdout=True, tty=False)
        return f"launched CPU busy-loop in {target} for {duration_s}s"

    async def oom(self, service: str) -> str:
        from kubernetes.stream import stream
        pods = self.v1.list_namespaced_pod(self.namespace, label_selector=f"app={service}").items
        if not pods:
            raise RuntimeError(f"no pods for {service}")
        target = pods[0].metadata.name
        cmd = ["/bin/sh", "-c", "python3 -c \"b=bytearray(); \n[b.extend(bytes(10**7)) for _ in range(10000)]\" &"]
        stream(self.v1.connect_get_namespaced_pod_exec, target, self.namespace,
               command=cmd, stderr=True, stdin=False, stdout=True, tty=False)
        return f"triggered memory allocation beyond limit in {target} (kubelet should OOM-kill it)"

    async def dependency_failure(self, service: str) -> str:
        self.apps.patch_namespaced_deployment_scale(service, self.namespace, {"spec": {"replicas": 0}})
        return f"scaled deployment/{service} to 0 replicas"

    async def revert_dependency_failure(self, service: str) -> str:
        self.apps.patch_namespaced_deployment_scale(service, self.namespace, {"spec": {"replicas": 3}})
        return f"scaled deployment/{service} back to 3 replicas"

    async def _patch_env(self, service: str, name: str, value: str) -> str:
        self.apps.patch_namespaced_deployment(service, self.namespace, {
            "spec": {"template": {"spec": {"containers": [{"name": service, "env": [{"name": name, "value": value}]}]}}}
        })
        return f"patched deployment/{service} env {name}={value}"

    async def network_latency(self, service: str, ms: int) -> str:
        return await self._patch_env(service, "CHAOS_INJECT", "latency")

    async def packet_loss(self, service: str, percent: int) -> str:
        # app-level substitution per doc §11 Phase 5 Step 6 "easy, honest" option;
        # documented as such rather than claiming true tc netem packet loss.
        return await self._patch_env(service, "CHAOS_INJECT", "error")

    async def revert_network_fault(self, service: str) -> str:
        return await self._patch_env(service, "CHAOS_INJECT", "")

    async def az_blackhole(self, zone: str) -> str:
        nodes = self.v1.list_node(label_selector=f"topology.kubernetes.io/zone={zone}").items
        for n in nodes:
            self.v1.patch_node(n.metadata.name, {"spec": {"unschedulable": True}})
        return f"cordoned {len(nodes)} node(s) in zone {zone} (PDBs limit the resulting drain's impact)"

    async def revert_az_blackhole(self, zone: str) -> str:
        nodes = self.v1.list_node(label_selector=f"topology.kubernetes.io/zone={zone}").items
        for n in nodes:
            self.v1.patch_node(n.metadata.name, {"spec": {"unschedulable": False}})
        return f"uncordoned {len(nodes)} node(s) in zone {zone}"

    async def region_failure(self) -> str:
        return await self._patch_env("api-gateway", "REGION_HEALTH_OVERRIDE", "unhealthy")

    async def revert_region_failure(self) -> str:
        return await self._patch_env("api-gateway", "REGION_HEALTH_OVERRIDE", "healthy")


def build_backend() -> FaultBackend:
    if os.getenv("KUBERNETES_SERVICE_HOST"):
        logger.info("running inside a cluster — using KubernetesBackend")
        return KubernetesBackend(namespace=os.getenv("TARGET_NAMESPACE", "rideflow"))
    logger.info("no Kubernetes API detected — using LocalBackend against docker-compose")
    return LocalBackend()
