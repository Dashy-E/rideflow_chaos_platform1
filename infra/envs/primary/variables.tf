variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "rideflow-primary"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 8
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT — see doc §14.2 (spot for cost during dev) and §15 risk #11 (on-demand for measured chaos runs)."
  type        = string
  default     = "ON_DEMAND"
}

# --- DynamoDB Global Tables ---
# This env owns the ONE creation of the Global Tables (see infra/modules/data
# comments). List the secondary region here so replicas are provisioned
# there automatically; infra/envs/secondary does not instantiate this module.
variable "dynamodb_replica_regions" {
  type    = list(string)
  default = ["ap-southeast-1"]
}
