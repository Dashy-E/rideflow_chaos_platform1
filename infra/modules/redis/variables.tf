variable "cluster_name" {
  description = "Used as a naming prefix for the ElastiCache subnet group / cluster."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the ElastiCache subnet group (doc §5.2: 'Data Subnets')."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups (typically the EKS node security group) permitted to reach Redis on port 6379."
  type        = list(string)
  default     = []
}

variable "node_type" {
  description = "cache.t4g.micro per doc §7.1 (single-node, cluster-mode off)."
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
