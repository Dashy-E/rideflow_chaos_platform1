# deploy/k8s

This directory intentionally has **no vendored manifests**. The platform
components listed in doc §7.2 (`platform` namespace: AWS Load Balancer
Controller, Cluster Autoscaler, metrics-server) plus `kube-prometheus-stack`
(observability workstream) are third-party systems installed straight from
their upstream Helm charts, per doc §11 Phase 2 step 3 — vendoring a copy of
someone else's CRDs and manifests into this repo would just rot out of date.

The `AWS Load Balancer Controller`, `Cluster Autoscaler`, and
`metrics-server` releases are already wired up as `helm_release` resources
in `infra/envs/primary/main.tf` and `infra/envs/secondary/main.tf` (using
the IRSA roles the `eks` Terraform module creates) — you normally don't
need to run these by hand. They're listed here for reference, for local
`kind` development, and for anyone who wants to manage them outside
Terraform.

## Local (`kind`) — Phase 0 setup (doc §11 Phase 0 step 4)

```bash
kind create cluster --name rideflow --config deploy/kind-config.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/metrics-server/latest/download/components.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kps prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace
```

## AWS (EKS) — platform components

```bash
# AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n platform \
  --set clusterName=<cluster-name> \
  --set region=<region> \
  --set vpcId=<vpc-id> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<lb-controller-irsa-role-arn>

# Cluster Autoscaler
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n platform \
  --set autoDiscovery.clusterName=<cluster-name> \
  --set awsRegion=<region> \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<cluster-autoscaler-irsa-role-arn>

# metrics-server (HPA needs this even with the Prometheus adapter present)
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update
helm install metrics-server metrics-server/metrics-server -n platform

# kube-prometheus-stack (observability namespace — Prometheus, Alertmanager,
# Grafana; doc §9.4/§9.5)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kps prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace
```

The `<...-irsa-role-arn>` values come out of `terraform output` in
`infra/envs/primary` / `infra/envs/secondary`
(`lb_controller_irsa_role_arn`, `cluster_autoscaler_irsa_role_arn`).

## Application deployment

The five RideFlow services, the chaos injector, and the four namespaces are
all deployed as one umbrella Helm release — see `deploy/helm/rideflow/`.

```bash
helm upgrade --install rideflow deploy/helm/rideflow -n rideflow --create-namespace
# secondary region:
helm upgrade --install rideflow deploy/helm/rideflow -n rideflow \
  -f deploy/helm/rideflow/values-secondary.yaml
```
