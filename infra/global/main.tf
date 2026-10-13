# infra/global
#
# Global resources that must survive a region teardown (doc §7.4 / §14.3
# "make down" discipline): the Route 53 hosted zone + failover DNS, IAM OIDC
# trust for GitHub Actions (keyless deploys per doc §11 Phase 6), and the 5
# ECR repositories with scan-on-push + cross-region replication.

locals {
  common_tags = {
    Project = "rideflow"
    Scope   = "global"
  }
}

# ---------------------------------------------------------------------------
# Route 53 — hosted zone + (once ALBs exist) failover records
# ---------------------------------------------------------------------------

module "dns" {
  source = "../modules/dns"

  create_zone              = true
  create_failover_records  = var.primary_alb_dns_name != "" && var.secondary_alb_dns_name != ""
  domain_name              = var.domain_name
  record_name              = var.record_name

  primary_alb_dns_name   = var.primary_alb_dns_name
  primary_alb_zone_id    = var.primary_alb_zone_id
  secondary_alb_dns_name = var.secondary_alb_dns_name
  secondary_alb_zone_id  = var.secondary_alb_zone_id

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM OIDC provider for GitHub Actions (keyless CI/CD, doc §11 Phase 6)
# ---------------------------------------------------------------------------

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to the main branch of this repo only — least privilege.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "rideflow-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  tags               = local.common_tags
}

# Least-privilege deploy policy: push to ECR, read/describe EKS clusters,
# and assume the eks:AccessEntry identity to run kubectl/helm. It cannot
# create/destroy infrastructure — Terraform applies are run by humans (or a
# separate, more tightly scoped OIDC role) per doc §15 non-goals ("no
# production-grade security posture" — this is deliberately minimal, not
# exhaustive).
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EKSDescribe"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
      "eks:ListClusters",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EKSAccess"
    effect = "Allow"
    actions = [
      "eks:AccessKubernetesApi",
    ]
    resources = [
      "arn:aws:eks:*:*:cluster/rideflow-primary",
      "arn:aws:eks:*:*:cluster/rideflow-secondary",
    ]
  }
}

resource "aws_iam_policy" "github_actions_deploy" {
  name        = "rideflow-github-actions-deploy"
  description = "Least-privilege policy for CI/CD: ECR push + kubectl/helm access to the two RideFlow clusters."
  policy      = data.aws_iam_policy_document.github_actions_deploy.json
}

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}

# ---------------------------------------------------------------------------
# ECR — 5 application repos, scan-on-push, cross-region replication
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  for_each = toset(var.ecr_repo_names)

  name                 = "rideflow/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Service = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_replication_configuration" "this" {
  replication_configuration {
    rule {
      destination {
        region      = var.secondary_region
        registry_id = data.aws_caller_identity.current.account_id
      }
    }
  }
}

data "aws_caller_identity" "current" {}
