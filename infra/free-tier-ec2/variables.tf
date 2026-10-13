variable "region" {
  description = "AWS region. Free tier applies in every region; ap-south-1 (Mumbai) matches the original spec."
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "Free Tier eligible: t2.micro (classic Free Tier, 750 hrs/month for 12 months on a new account) or t3.micro depending on your account's offer. Check the AWS Billing > Free Tier page for which one your account actually gets before applying."
  type        = string
  default     = "t2.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH in. Defaults to open (0.0.0.0/0) for convenience since this is a throwaway demo box — narrow this to your own IP/32 if you're leaving it up for more than a demo session."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_app_cidr" {
  description = "CIDR allowed to reach the app/dashboard/Grafana/Prometheus ports. Open by default so you can demo from anywhere; narrow it if this stays up unattended."
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_path" {
  description = "Local path to the RideFlow repo root, uploaded to the instance via the file provisioner."
  type        = string
  default     = "../../"
}

variable "volume_size_gb" {
  description = "Root EBS volume size. Free Tier covers up to 30GB of gp2/gp3 per month."
  type        = number
  default     = 30
}
