variable "domain_name" {
  description = "Root domain for the hosted zone, e.g. rideflow.example."
  type        = string
  default     = "rideflow.example"
}

variable "record_name" {
  description = "Fully-qualified record name that clients hit, per doc §7.3."
  type        = string
  default     = "api.rideflow.example"
}

variable "create_zone" {
  description = "Whether this module should create the hosted zone (true when called from infra/global). Set false and pass zone_id if the zone already exists."
  type        = bool
  default     = true
}

variable "create_failover_records" {
  description = <<-EOT
    Whether to create the health checks + PRIMARY/SECONDARY failover record
    set. Set false until both regions' ALB DNS names/zone IDs are known
    (they don't exist until infra/envs/primary and infra/envs/secondary
    have been applied) — see infra/global/README notes.
  EOT
  type    = bool
  default = true
}

variable "zone_id" {
  description = "Existing hosted zone ID to use when create_zone = false."
  type        = string
  default     = ""
}

variable "primary_alb_dns_name" {
  description = "DNS name of the primary region's ALB (from the Kubernetes Ingress / AWS LB Controller output). Required when create_failover_records = true."
  type        = string
  default     = ""
}

variable "primary_alb_zone_id" {
  description = "Hosted zone ID of the primary region's ALB (for the ALIAS record). Required when create_failover_records = true."
  type        = string
  default     = ""
}

variable "secondary_alb_dns_name" {
  description = "DNS name of the secondary region's ALB. Required when create_failover_records = true."
  type        = string
  default     = ""
}

variable "secondary_alb_zone_id" {
  description = "Hosted zone ID of the secondary region's ALB. Required when create_failover_records = true."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Path checked by both Route 53 health checks. Doc §7.3: aggregate regional health via api-gateway's /healthz/region."
  type        = string
  default     = "/healthz/region"
}

variable "health_check_port" {
  type    = number
  default = 443
}

variable "health_check_interval" {
  description = "10s ('fast' interval) per doc §7.3 — the minimum available, and it drives the detection floor."
  type        = number
  default     = 10
}

variable "health_check_failure_threshold" {
  description = "3 consecutive failures = 30s minimum detection, per doc §7.3."
  type        = number
  default     = 3
}

variable "record_ttl" {
  description = "DNS TTL in seconds. Lower is better for failover speed, worse for query cost (doc §7.3)."
  type        = number
  default     = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
