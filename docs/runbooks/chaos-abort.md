# Runbook: Emergency chaos abort

The fastest path is always the API — it's what the dashboard's red button calls:

```bash
curl -X POST http://localhost:9000/abort         # local
curl -X POST http://<chaos-svc>/abort            # in-cluster
```

If the injector itself is unresponsive, follow the full sequence from
doc Appendix D:

```bash
# 1. Global kill switch
kubectl -n chaos patch configmap chaos-config --type merge -p '{"data":{"enabled":"false"}}'

# 2. Revert all active faults (if the API is reachable)
curl -XPOST http://<chaos-svc>/abort

# 3. Verify no faults remain
curl -s http://<chaos-svc>/runs | jq '.[] | select(.status=="running")'

# 4. If the injector is itself unhealthy, remove it entirely
kubectl -n chaos scale deployment/chaos-injector --replicas=0

# 5. Clear any orphaned tc rules (network experiments, if the privileged
#    DaemonSet variant was used instead of the app-level fallback)
kubectl -n chaos delete daemonset chaos-netem

# 6. Force-restore all deployments to declared state
helm -n rideflow rollback rideflow

# 7. Uncordon any cordoned nodes
kubectl get nodes -o name | xargs -I{} kubectl uncordon {}
```

Never run an untested experiment live during a demo — rehearse with `?dryRun=true`
first. The injector also auto-reverts any fault it finds still active on its
own restart (`chaos-injector/app/engine.py`, `find_orphaned_fault`), so a
crashed injector process is not itself a stuck-fault scenario in most cases.
