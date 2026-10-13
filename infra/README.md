# RideFlow Infrastructure (Terraform)

This directory provisions the AWS infrastructure described in
`RideFlow-Chaos-Platform-Documentation.md` §5, §7, and §11 Phase 2/4.
**Nothing here has been applied** — no AWS credentials are available in the
environment this was written in. It is written to be correct and ready for
`terraform init && terraform apply` once you have an AWS account.

## Layout

```
infra/
├── modules/
│   ├── vpc/      # VPC, 3 public + 3 private subnets, IGW, single NAT GW
│   ├── eks/      # EKS 1.30 cluster, OIDC provider, managed node group, IRSA roles
│   ├── redis/    # ElastiCache subnet group + single-node Redis (geo index)
│   ├── data/     # DynamoDB Global Tables: users, rides
│   └── dns/      # Route 53 zone, health checks, failover record set
├── envs/
│   ├── primary/     # ap-south-1 — full region, owns the DynamoDB Global Tables
│   └── secondary/   # ap-southeast-1 — warm standby, smaller node group
└── global/          # Route 53 zone, GitHub Actions OIDC + deploy role, ECR repos
```

## Apply order

**global → primary → secondary**, always. Global resources (Route 53 zone,
IAM, ECR) live in their own root module and state file specifically so that
tearing down a region (`terraform destroy` in `envs/primary` or
`envs/secondary`) can never delete them — see doc §7.4.

```bash
# 0. One-time: create the Terraform state backend (see infra/global/backend.tf
#    for the exact commands) — an S3 bucket with versioning + a DynamoDB
#    lock table. Do this by hand; Terraform can't create the backend it
#    lives in.

# 1. Global resources
cd infra/global
cp terraform.tfvars.example terraform.tfvars   # fill in domain, GitHub org
terraform init
terraform apply

# 2. Primary region (ap-south-1)
cd ../envs/primary
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
aws eks update-kubeconfig --region ap-south-1 --name rideflow-primary
kubectl get nodes -o wide     # verify 3 nodes across 3 AZs

# 3. Secondary region (ap-southeast-1) — only when you need failover testing
cd ../secondary
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

# 4. Deploy the application (see deploy/helm/rideflow) to both clusters,
#    then look up each region's ALB DNS name + hosted zone ID and re-apply
#    infra/global with primary_alb_* / secondary_alb_* set, to wire up
#    Route 53 failover. See infra/global/terraform.tfvars.example.
```

### Teardown order (reverse)

```bash
cd infra/envs/secondary && terraform destroy
cd ../primary            && terraform destroy
cd ../../global           && terraform destroy   # only if tearing down entirely
```

Destroy `envs/secondary` first — per doc §14.2, the secondary region should
normally only be provisioned for failover experiments (weeks 5-6, 10), not
run continuously.

## Design notes worth knowing before you touch this

- **DynamoDB Global Tables are created exactly once**, from
  `infra/envs/primary`, with `ap-southeast-1` listed in
  `dynamodb_replica_regions`. `infra/envs/secondary` does **not**
  instantiate the `data` module — a Global Table's replica set is a single
  logical resource; creating it from both envs would conflict. See the
  header comment in `infra/modules/data/main.tf`.
- **Route 53 failover records require both ALBs to exist first.** The
  `infra/global` root module creates the hosted zone unconditionally, but
  skips the health checks + failover record set until
  `primary_alb_dns_name` / `secondary_alb_dns_name` are non-empty. Apply
  `global` once early (zone only), deploy the app to both regions, then
  re-apply `global` with the ALB details filled in.
- **State backend**: S3 + DynamoDB locking, all three root modules sharing
  one bucket in the **primary region** (doc §7.4), distinguished by `key`.
  The bucket/table names in every `backend.tf` are placeholders
  (`rideflow-tfstate-REPLACE-ME`) — replace them with a real, globally
  unique bucket name before first `init`.
- **Platform controllers** (AWS Load Balancer Controller, Cluster
  Autoscaler, metrics-server) are installed via `helm_release` resources
  in each env's `main.tf`, using the IRSA roles the `eks` module creates.
  This mirrors doc §11 Phase 2 step 3. `kube-prometheus-stack` is
  intentionally **not** installed here — it's part of the observability
  workstream, not this infra layer.

## Cost warnings — read doc §14 before applying anything

This is a **real AWS bill**, not a simulation. Doc §14.1 estimates ~$460/mo
if the full two-region architecture runs 24×7. Doc §14.2's cost-optimised
model (spot nodes, scheduled uptime, single NAT, secondary region only
during failover weeks) gets the realistic project-lifetime cost down to
**$60-100 total**. Before running `terraform apply` against a real account:

1. Set an AWS Budget alarm (doc §14.3 recommends $25/month with SNS email)
   **before** anything else.
2. Never leave `envs/secondary` running continuously — it exists for
   failover experiments, not steady state.
3. Run a `make down` target (or equivalent) at the end of every working
   session — scale node groups to zero and `terraform destroy` ALBs/NAT.
   ALBs and NAT Gateways bill hourly whether or not anything is deployed;
   they are the two most common sources of a surprise bill.
4. Tag every resource `Project=rideflow` (already default-tagged by every
   root module here) and review Cost Explorer weekly grouped by tag.
5. Prove `terraform destroy` + re-apply works at least once — it's the
   actual test of whether this is real IaC, and it saves money overnight.
