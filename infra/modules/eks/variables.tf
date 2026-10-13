variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control-plane version. Pinned per doc §7.1 / §15 risk #10 — do not bump mid-project."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets the managed node group's EC2 instances launch into."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets, added to the cluster's subnet list so the ALB controller can provision internet-facing ALBs there."
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_disk_size_gb" {
  type    = number
  default = 20
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
  description = "ON_DEMAND or SPOT. Doc §14.2 recommends SPOT for cost during development; use ON_DEMAND for the final measured chaos runs (§15 risk #11)."
  type        = string
  default     = "ON_DEMAND"
}

variable "enable_cluster_autoscaler_irsa" {
  description = "Create the IRSA role + policy for the Cluster Autoscaler service account."
  type        = bool
  default     = true
}

variable "enable_lb_controller_irsa" {
  description = "Create the IRSA role + policy for the AWS Load Balancer Controller service account."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
