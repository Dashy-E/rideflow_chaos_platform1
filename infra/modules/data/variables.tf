variable "table_name_prefix" {
  description = "Prefix for table names, e.g. \"rideflow\" -> rideflow-users, rideflow-rides."
  type        = string
  default     = "rideflow"
}

variable "replica_regions" {
  description = <<-EOT
    Additional AWS regions to replicate these tables into as DynamoDB Global
    Tables (v2 / replica blocks). This module should be instantiated exactly
    ONCE for the whole platform (from infra/envs/primary) with the secondary
    region listed here — a Global Table's replica set is a single logical
    resource, so it must not also be created from infra/envs/secondary.
  EOT
  type    = list(string)
  default = []
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST (on-demand) per doc §7.1."
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "point_in_time_recovery" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
