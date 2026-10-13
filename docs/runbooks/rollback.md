# Runbook: Rollback

## Kubernetes / Helm
```bash
helm -n rideflow history rideflow
helm -n rideflow rollback rideflow <REVISION>
kubectl -n rideflow rollout status deployment/ride-service   # repeat per service if needed
```

## Single service, without a full chart rollback
```bash
kubectl -n rideflow rollout undo deployment/<service-name>
kubectl -n rideflow rollout status deployment/<service-name>
```

## CI/CD
The `deploy.yml` pipeline uses `helm upgrade --install ... --wait --timeout 5m`,
so a deploy that fails to reach Ready within 5 minutes fails the pipeline
without ever completing the swap — Kubernetes's own rolling-update
`maxUnavailable: 0` means old pods are never removed until new ones are Ready,
so a bad deploy self-limits its blast radius even before a manual rollback.

## Local (docker-compose)
```bash
git checkout <previous-good-commit> -- services/<service>
make down && make up
```
