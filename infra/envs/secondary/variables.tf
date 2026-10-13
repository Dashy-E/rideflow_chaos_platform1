variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "rideflow-secondary"
}

variable "vpc_cidr" {
  description = "Non-overlapping CIDR vs primary's 10.0.0.0/16 — doc §7.1 (enables future peering)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}

# Doc §5.4 deployment topology: secondary node group is 2 × t3.medium,
# min 2 / max 6 (smaller than primary's 3/3/8 — warm standby).
variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}
