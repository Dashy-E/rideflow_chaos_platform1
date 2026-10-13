variable "region" {
  description = "Region the global provider operates from. IAM/Route53 are global services; ECR repos below are created here and replicated to var.secondary_region."
  type        = string
  default     = "ap-south-1"
}

variable "secondary_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "domain_name" {
  type    = string
  default = "rideflow.example"
}

variable "record_name" {
  type    = string
  default = "api.rideflow.example"
}

variable "github_org" {
  description = "GitHub org/user that owns the RideFlow repo, for the OIDC trust policy."
  type        = string
  default     = "REPLACE_ME_github_org"
}

variable "github_repo" {
  description = "GitHub repo name (without org), for the OIDC trust policy."
  type        = string
  default     = "RideFlow-Chaos-Platform"
}

variable "ecr_repo_names" {
  description = "The 5 application image repos (doc §7.1)."
  type        = list(string)
  default = [
    "api-gateway",
    "user-service",
    "ride-service",
    "driver-service",
    "pricing-service",
  ]
}

# --- Failover records: filled in only after both regions' ALBs exist. ---
# Leave these blank ("") on the first `terraform apply` (only the zone,
# IAM, and ECR resources will be created — the dns module's record
# resources are skipped via count while these are empty). After
# `infra/envs/primary` and `infra/envs/secondary` are applied, look up each
# ALB's DNS name and hosted zone ID (`kubectl -n rideflow get ingress` then
# `aws elbv2 describe-load-balancers`) and re-apply this root module with
# them populated to wire up Route 53 failover.

variable "primary_alb_dns_name" {
  type    = string
  default = ""
}

variable "primary_alb_zone_id" {
  type    = string
  default = ""
}

variable "secondary_alb_dns_name" {
  type    = string
  default = ""
}

variable "secondary_alb_zone_id" {
  type    = string
  default = ""
}
