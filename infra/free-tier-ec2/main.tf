terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "aws" {
  region = var.region
}

# ---------------------------------------------------------------------------
# Deploy-only SSH keypair — generated fresh so you don't need a pre-existing
# AWS keypair. The private key is written locally (gitignored) and used only
# by the provisioners below to bootstrap the box.
# ---------------------------------------------------------------------------
resource "tls_private_key" "deploy" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.deploy.private_key_pem
  filename        = "${path.module}/rideflow-ec2-key.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "deploy" {
  key_name   = "rideflow-demo-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  public_key = tls_private_key.deploy.public_key_openssh

  lifecycle {
    ignore_changes = [key_name] # avoid replacing on every apply due to the timestamp
  }
}

# ---------------------------------------------------------------------------
# Use the account's default VPC — no new VPC/IGW/NAT gateway, which keeps
# this genuinely free (NAT gateways alone are ~$33/mo and are NOT free tier).
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "rideflow" {
  name        = "rideflow-demo"
  description = "RideFlow free-tier demo box — SSH + the app/dashboard/observability ports"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # api-gateway, dashboard, grafana, prometheus, chaos-injector, security-injector
  ingress {
    description = "RideFlow app ports"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = [var.allowed_app_cidr]
  }
  dynamic "ingress" {
    for_each = toset([8080, 5173, 9000, 9001, 9090])
    content {
      description = "RideFlow app port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.allowed_app_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "rideflow", Name = "rideflow-demo" }
}

resource "aws_instance" "rideflow" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deploy.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.rideflow.id]
  associate_public_ip_address = true
  user_data                   = file("${path.module}/cloud-init.sh")

  root_block_device {
    volume_size = var.volume_size_gb
    volume_type = "gp3"
  }

  tags = { Project = "rideflow", Name = "rideflow-demo" }
}

# ---------------------------------------------------------------------------
# Upload the repo and bring the stack up — same docker-compose.yml that
# already works locally, nothing environment-specific to change.
# ---------------------------------------------------------------------------
resource "null_resource" "deploy" {
  depends_on = [aws_instance.rideflow]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.deploy.private_key_pem
    host        = aws_instance.rideflow.public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "file" {
    source      = var.project_path
    destination = "/home/ubuntu/rideflow"
  }

  provisioner "remote-exec" {
    inline = [
      "cd /home/ubuntu/rideflow && sudo docker compose up -d --build",
    ]
  }

  triggers = {
    always_run = timestamp()
  }
}

output "public_ip" {
  value = aws_instance.rideflow.public_ip
}

output "dashboard_url" {
  value = "http://${aws_instance.rideflow.public_ip}:5173"
}

output "api_url" {
  value = "http://${aws_instance.rideflow.public_ip}:8080"
}

output "grafana_url" {
  value = "http://${aws_instance.rideflow.public_ip}:3001"
}

output "ssh_command" {
  value = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.rideflow.public_ip}"
}
