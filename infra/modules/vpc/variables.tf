variable "region" {
  description = "AWS region to deploy the VPC into."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster that will live in this VPC (used for subnet discovery tags)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. Must have exactly 3 entries."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Exactly 3 availability zones are required (3 public + 3 private subnets)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 3 public subnets, one per AZ, in the same order as var.azs."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the 3 private subnets, one per AZ, in the same order as var.azs."
  type        = list(string)
  default     = ["10.0.64.0/19", "10.0.96.0/19", "10.0.128.0/19"]
}

variable "tags" {
  description = "Common tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
