# RideFlow — Free-Tier EC2 Deployment

The single cheapest way to get RideFlow running on real AWS infrastructure:
one EC2 instance running the exact `docker-compose.yml` stack that already
works locally. No EKS, no NAT Gateway, no ElastiCache, no ALB — those are
what make the full spec's architecture cost money even when idle.

## Is this actually free?

Only if your AWS account is within its **Free Tier** allowance:
- `t2.micro` (or `t3.micro`, depending on which your account's Free Tier
  offer covers — check **Billing → Free Tier** in the AWS Console first):
  750 instance-hours/month, free for 12 months on a new account.
- 30GB of gp2/gp3 EBS storage: covered.
- Data transfer out: first 100GB/month covered.

If your account is *not* in its first 12 months, or you've already used your
free-tier EC2 hours, this becomes a genuinely cheap instance (a few cents/hr
for `t3.micro`) rather than free. **Check your account's Free Tier status
before running `terraform apply`.**

What you lose by not deploying the full spec: multi-region failover, EKS
orchestration, HPA/Cluster Autoscaler, ALB — those become "designed but not
deployed" in your report, backed by the local `kind` demo instead of a real
AWS deployment. What you keep: a genuinely live, publicly reachable RideFlow
instance with the chaos and security engines both fully working — real
evidence for a real link, not just localhost screenshots.

## Prerequisites

1. An AWS account with `aws configure` already run (**you** do this step —
   credentials are never entered on your behalf). Verify with:
   ```bash
   aws sts get-caller-identity
   ```
2. Terraform, installed.

## Deploy

```bash
cd infra/free-tier-ec2
terraform init
terraform apply
```

This will: generate a throwaway SSH keypair, launch the instance in your
account's default VPC (no new networking resources), wait for Docker to
install via cloud-init, upload the repo, and run
`docker compose up -d --build` on the box. Takes roughly 3-5 minutes.

On success, Terraform prints:
```
dashboard_url = "http://<public-ip>:5173"
api_url       = "http://<public-ip>:8080"
grafana_url   = "http://<public-ip>:3001"
ssh_command   = "ssh -i rideflow-ec2-key.pem ubuntu@<public-ip>"
```

## Security note

`allowed_ssh_cidr` and `allowed_app_cidr` default to `0.0.0.0/0` (open to
the internet) for demo convenience — this box is meant to go up, get
demoed/graded, and come back down. If you're leaving it running for more
than a session, narrow both to your own IP:

```bash
terraform apply -var="allowed_ssh_cidr=YOUR_IP/32" -var="allowed_app_cidr=YOUR_IP/32"
```

Also worth doing once it's up: run the security-injector's own attacks
against it (`curl -X POST http://<public-ip>:9001/attacks/.../run`) — the
`internal-endpoint-recon` finding becomes a real, honest result out here
instead of an expected-locally caveat, since every internal port really is
now reachable from the internet on a box configured this openly. Good
report material either way.

## Cost discipline

```bash
# stop billing without losing the instance (still counts toward free-tier hours if running... so actually destroy for real teardown)
terraform destroy
```

Run this at the end of every session unless you're actively demoing —
apply the same discipline as `make down` locally (see
docs/runbooks/teardown.md). Unlike the full EKS architecture, there's no
NAT Gateway/ALB ticking away in the background here — the only cost is the
instance itself, so `destroy` fully zeroes it out.

## Redeploying after a code change

Terraform's provisioners only re-run when the instance is recreated. For a
quick iteration loop once the box is up, it's faster to just SSH in and
re-sync:

```bash
scp -i rideflow-ec2-key.pem -r ../../services ../../chaos-injector ../../security-injector ../../docker-compose.yml ubuntu@<public-ip>:/home/ubuntu/rideflow/
ssh -i rideflow-ec2-key.pem ubuntu@<public-ip> "cd rideflow && sudo docker compose up -d --build"
```
