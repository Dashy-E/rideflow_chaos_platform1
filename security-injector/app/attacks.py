"""Attack modules. Every module only ever targets RideFlow's own services
(SERVICE_URLS below) — this tool has no concept of an external target and
cannot be pointed at anything else. That's what keeps this squarely in
"authorized self-testing of our own deployment" territory rather than a
general-purpose attack tool.

Each module returns a list of Findings. A Finding with passed=False means
"we found a real weakness" — that is the useful output of this tool, not a
bug in it. Several of these WILL come back vulnerable against the reference
app as shipped; that's an honest, reportable result (see docs/security/).
"""
import asyncio
import base64
import json
import time
import uuid

import httpx
import jwt as pyjwt

from .models import Finding

SERVICE_URLS = {
    "api-gateway": "http://api-gateway:8080",
    "user-service": "http://user-service:8081",
    "ride-service": "http://ride-service:8082",
    "driver-service": "http://driver-service:8083",
    "pricing-service": "http://pricing-service:8084",
}

KNOWN_DEFAULT_JWT_SECRET = "dev-secret-not-for-prod"  # the default in services/user-service/src/index.js


async def auth_bruteforce(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    gw = SERVICE_URLS["api-gateway"]
    email = f"brutetest-{uuid.uuid4().hex[:8]}@rideflow.test"
    password = "correct-horse-battery-staple"
    attempts = params.get("attempts", 25)

    r = await client.post(f"{gw}/v1/users", json={"email": email, "password": password})
    if r.status_code not in (201, 409):
        findings.append(Finding(check="setup", passed=False, detail=f"could not create test user (status {r.status_code})"))
        return findings

    statuses = []
    start = time.time()
    for i in range(attempts):
        r = await client.post(f"{gw}/v1/auth/login", json={"email": email, "password": f"wrong-{i}"})
        statuses.append(r.status_code)
    elapsed = time.time() - start

    blocked = sum(1 for s in statuses if s == 429)
    unauthorized = sum(1 for s in statuses if s == 401)

    if blocked == 0:
        findings.append(Finding(
            check="account_lockout_or_login_rate_limit",
            passed=False,
            detail=f"{attempts} wrong-password attempts against one account in {elapsed:.1f}s, "
                   f"all returned normally ({unauthorized} x 401, 0 rate-limited or locked out). "
                   f"No auth-specific brute-force defense exists — only the gateway's generic "
                   f"100 req/s per-IP limiter, which a slow/distributed brute-force would evade entirely.",
            evidence=f"status codes: {statuses[:10]}{'...' if len(statuses) > 10 else ''}",
        ))
    else:
        findings.append(Finding(
            check="account_lockout_or_login_rate_limit",
            passed=True,
            detail=f"{blocked}/{attempts} attempts were rate-limited",
        ))

    r = await client.post(f"{gw}/v1/auth/login", json={"email": email, "password": password})
    findings.append(Finding(
        check="legit_login_still_works_after_bruteforce",
        passed=r.status_code == 200,
        detail=f"correct-password login after the brute-force burst returned {r.status_code}",
    ))
    return findings


async def rate_limit_pressure(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    gw = SERVICE_URLS["api-gateway"]
    concurrency = params.get("concurrency", 60)
    waves = params.get("waves", 4)

    total, throttled = 0, 0
    async def hit():
        try:
            r = await client.get(f"{gw}/healthz")
            return r.status_code
        except Exception:
            return -1

    for _ in range(waves):
        results = await asyncio.gather(*(hit() for _ in range(concurrency)))
        total += len(results)
        throttled += sum(1 for s in results if s == 429)

    if throttled > 0:
        findings.append(Finding(
            check="gateway_rate_limiting",
            passed=True,
            detail=f"{throttled}/{total} requests across a {concurrency}x{waves} burst were throttled (429) "
                   f"by the gateway's per-IP token bucket — DoS-by-flood from a single source is mitigated.",
        ))
    else:
        findings.append(Finding(
            check="gateway_rate_limiting",
            passed=False,
            detail=f"0/{total} requests throttled under burst load — rate limiting did not engage "
                   f"(note: a distributed flood from many IPs would still bypass a per-IP limiter regardless).",
        ))
    return findings


async def jwt_tampering(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    gw = SERVICE_URLS["api-gateway"]
    email = f"jwttest-{uuid.uuid4().hex[:8]}@rideflow.test"
    password = "test-password-123"

    await client.post(f"{gw}/v1/users", json={"email": email, "password": password})
    r = await client.post(f"{gw}/v1/auth/login", json={"email": email, "password": password})
    if r.status_code != 200:
        findings.append(Finding(check="setup", passed=False, detail="could not obtain a legitimate token"))
        return findings
    real_token = r.json()["token"]
    real_payload = pyjwt.decode(real_token, options={"verify_signature": False})

    async def try_token(name: str, token: str, expect_rejected: bool = True):
        try:
            r = await client.get(f"{gw}/v1/users/me", headers={"Authorization": f"Bearer {token}"})
            accepted = r.status_code == 200
        except Exception:
            accepted = False
        passed = (not accepted) if expect_rejected else accepted
        findings.append(Finding(
            check=f"jwt_{name}",
            passed=passed,
            detail=f"token variant '{name}' was {'accepted' if accepted else 'rejected'} "
                   f"({'expected rejection' if expect_rejected else 'expected acceptance'})",
        ))

    # 1. alg:none — classic JWT bypass
    header_none = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).rstrip(b"=")
    payload_b64 = base64.urlsafe_b64encode(json.dumps(real_payload).encode()).rstrip(b"=")
    alg_none_token = f"{header_none.decode()}.{payload_b64.decode()}."
    await try_token("alg_none", alg_none_token)

    # 2. garbage signature
    parts = real_token.split(".")
    tampered = f"{parts[0]}.{parts[1]}.garbage-signature"
    await try_token("garbage_signature", tampered)

    # 3. payload tampered (escalate tier) but keep original signature — should fail sig check
    evil_payload = dict(real_payload, tier="PLUS", sub=real_payload["sub"])
    evil_payload_b64 = base64.urlsafe_b64encode(json.dumps(evil_payload).encode()).rstrip(b"=")
    resigned_wrong = f"{parts[0]}.{evil_payload_b64.decode()}.{parts[2]}"
    await try_token("payload_tamper_stale_sig", resigned_wrong)

    # 4. forged with the known default dev secret — this is the real finding
    forged = pyjwt.encode({"sub": real_payload["sub"], "tier": "PLUS"}, KNOWN_DEFAULT_JWT_SECRET, algorithm="HS256")
    try:
        r = await client.get(f"{gw}/v1/users/me", headers={"Authorization": f"Bearer {forged}"})
        accepted = r.status_code == 200
    except Exception:
        accepted = False
    findings.append(Finding(
        check="jwt_forged_with_default_secret",
        passed=not accepted,
        detail=("CRITICAL: a token forged with the hardcoded default JWT secret "
                "(services/user-service/src/index.js JWT_SECRET fallback) was accepted. "
                "This secret MUST be overridden via the JWT_SECRET env var / a real secrets "
                "manager before any non-local deployment.") if accepted else
               "forged token using the known default secret was rejected (JWT_SECRET was overridden)",
        evidence="attempted forgery using the literal default fallback string shipped in source",
    ))
    return findings


async def injection_fuzz(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    gw = SERVICE_URLS["api-gateway"]
    payloads = [
        "' OR '1'='1", "'; DROP TABLE rides; --", "<script>alert(1)</script>",
        "{{7*7}}", "../../../etc/passwd", "$(rm -rf /)", "\x00\x01\x02", "A" * 20000,
    ]
    crashed, leaked_stack, handled = 0, 0, 0
    for p in payloads:
        try:
            r = await client.post(f"{gw}/v1/rides", json={
                "userId": p, "pickup": {"lat": 19.0, "lng": 72.0}, "drop": {"lat": 19.1, "lng": 72.1},
            }, timeout=5.0)
            body = r.text.lower()
            if r.status_code >= 500:
                crashed += 1
                if "traceback" in body or "file \"" in body or "at " in body and "stack" in body:
                    leaked_stack += 1
            else:
                handled += 1
        except httpx.TimeoutException:
            crashed += 1
        except Exception:
            crashed += 1

    findings.append(Finding(
        check="injection_payload_handling",
        passed=crashed == 0,
        detail=f"{handled}/{len(payloads)} malformed/injection-style payloads handled without a 5xx; "
               f"{crashed} caused server errors" + (f" ({leaked_stack} leaked stack traces)" if leaked_stack else ""),
    ))
    if leaked_stack:
        findings.append(Finding(
            check="stack_trace_disclosure",
            passed=False,
            detail=f"{leaked_stack} response(s) included what looks like an internal stack trace — "
                   f"disable framework debug mode in any non-local deployment.",
        ))
    return findings


async def idor_probe(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    gw = SERVICE_URLS["api-gateway"]
    ride_svc = SERVICE_URLS["ride-service"]

    r = await client.post(f"{gw}/v1/rides", json={
        "userId": "victim-user", "pickup": {"lat": 19.0, "lng": 72.0}, "drop": {"lat": 19.1, "lng": 72.1},
    })
    if r.status_code not in (200, 201, 202):
        findings.append(Finding(check="setup", passed=False, detail="could not create a target ride"))
        return findings
    ride_id = r.json()["rideId"]

    # can an unauthenticated caller read someone else's ride through the public API?
    r = await client.get(f"{gw}/v1/rides/{ride_id}")
    findings.append(Finding(
        check="idor_ride_read_via_gateway",
        passed=r.status_code in (401, 403),
        detail=f"unauthenticated GET /v1/rides/{{id}} for another user's ride returned {r.status_code} "
               f"(expected 401/403; ride-service currently has no per-user ownership check at all)",
    ))

    # defense-in-depth check: is the internal service reachable directly, bypassing the gateway entirely?
    try:
        r2 = await client.get(f"{ride_svc}/internal/rides/{ride_id}", timeout=3.0)
        direct_reachable = r2.status_code == 200
    except Exception:
        direct_reachable = False
    findings.append(Finding(
        check="internal_service_defense_in_depth",
        passed=not direct_reachable,
        detail=("ride-service's /internal/* API is directly reachable on its own port with zero auth, "
                "completely bypassing api-gateway's JWT check. In this docker-compose setup that's expected "
                "(all ports are published to the host for demoability); in the real EKS deployment this "
                "still holds for anything in-namespace, since only api-gateway is fronted by the ALB — "
                "internal calls between services carry no service-to-service auth. A NetworkPolicy or "
                "mTLS layer would close this; documented as a known gap, not fixed, per doc §15.1 "
                "(no service mesh) — flag it explicitly in the report rather than silently relying on it.")
               if direct_reachable else "internal service was not directly reachable",
        evidence=f"GET {ride_svc}/internal/rides/{ride_id} -> {'200' if direct_reachable else 'unreachable'}",
    ))
    return findings


async def internal_endpoint_recon(client: httpx.AsyncClient, params: dict) -> list[Finding]:
    findings = []
    probes = [
        ("ride-service", "/internal/rides/nonexistent-id"),
        ("user-service", "/internal/users/nonexistent-id/validate"),
        ("driver-service", "/internal/match"),
        ("pricing-service", "/internal/quote"),
        ("ride-service", "/admin/chaos"),
        ("pricing-service", "/admin/chaos"),
        ("api-gateway", "/admin/region"),
    ]
    exposed = []
    for service, path in probes:
        url = SERVICE_URLS[service] + path
        try:
            r = await client.get(url, timeout=3.0)
            reachable = r.status_code < 502
        except Exception:
            reachable = False
        if reachable:
            exposed.append(f"{service}{path} ({r.status_code})")

    findings.append(Finding(
        check="internal_admin_endpoint_exposure",
        passed=len(exposed) == 0,
        detail=(f"{len(exposed)} internal/admin endpoint(s) answered directly, unauthenticated, on their "
                f"service port. Expected in this local docker-compose topology (see idor_probe finding); "
                f"in a real deployment these must never be reachable from outside the cluster network — "
                f"verify with a NetworkPolicy or by confirming only api-gateway has an Ingress/ALB target group.")
               if exposed else "no internal endpoints were reachable from outside",
        evidence=", ".join(exposed) if exposed else None,
    ))
    return findings


ATTACK_FUNCS = {
    "auth_bruteforce": auth_bruteforce,
    "rate_limit_pressure": rate_limit_pressure,
    "jwt_tampering": jwt_tampering,
    "injection_fuzz": injection_fuzz,
    "idor_probe": idor_probe,
    "internal_endpoint_recon": internal_endpoint_recon,
}
