# Runbook: Manual region failover (test or real)

## Force the primary region unhealthy
```bash
# Kubernetes / real deploy
kubectl -n rideflow set env deployment/api-gateway REGION_HEALTH_OVERRIDE=unhealthy

# Local docker-compose
curl -X POST localhost:8080/admin/region?state=unhealthy
```

## Watch resolution flip (AWS only — Route 53 health check + failover record)
```bash
watch -n2 'dig +short api.rideflow.example'
```
Expect the theoretical floor from doc §7.3: 30s (3×10s health-check failures)
+ up to 60s (DNS TTL) + client reconnect ≈ **60–95s**. This is inherent to
DNS-based failover — report it as a finding, not a defect (see ADR-0002).

## Restore
```bash
kubectl -n rideflow set env deployment/api-gateway REGION_HEALTH_OVERRIDE=healthy
# or locally:
curl -X POST localhost:8080/admin/region?state=healthy
```

## Automated version
The same toggle is fault type `region_failure` in the chaos injector —
`POST /experiments/region-failure-primary/run` (experiment E7,
`experiments/e7-region-failure-primary.yaml`) drives this exact sequence and
measures MTTD/MTTR automatically.
