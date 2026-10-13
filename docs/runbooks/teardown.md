# Runbook: Teardown (cost discipline — run this every session)

ALBs and NAT Gateways bill hourly whether or not anything is deployed. This is
the single most common source of a surprise AWS bill on this project (doc §14.3).

## Local
```bash
make down          # docker compose down
make kind-down      # delete the kind cluster
```

## AWS — end of a work session (cheap, fast)
```bash
# scale node groups to zero, keep everything else provisioned
aws eks update-nodegroup-config --cluster-name rideflow-primary \
  --nodegroup-name <ng-name> --scaling-config minSize=0,maxSize=8,desiredSize=0
```

## AWS — full teardown (end of project, or between major milestones)
```bash
cd infra/envs/secondary && terraform destroy
cd infra/envs/primary && terraform destroy
cd infra/global && terraform destroy   # last — this is DNS + IAM + ECR
```
Prove `terraform destroy` followed by re-`apply` works at least once during
the project — that round-trip is the actual test of whether the IaC is
correct, and it's also how you avoid paying for idle infrastructure overnight.

## Backstop
A daily 22:00 IST EventBridge rule should scale all node groups to zero as a
safety net for the day someone forgets to run this manually (doc §14.3).
