# infra/modules/eks
#
# EKS cluster (v1.30 pinned — doc §15 risk #10), OIDC provider for IRSA,
# a single managed node group (t3.medium, min 3 / desired 3 / max 8) tagged
# for Cluster Autoscaler auto-discovery, and IRSA roles for the two platform
# controllers that get installed via Helm afterwards (AWS Load Balancer
# Controller, Cluster Autoscaler) per doc §7.1 / Phase 2 step 3.

locals {
  common_tags = merge(var.tags, {
    "Project" = "rideflow"
    "Module"  = "eks"
  })

  cluster_subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)
}

# ---------------------------------------------------------------------------
# Cluster IAM role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# EKS cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = local.cluster_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ---------------------------------------------------------------------------
# OIDC provider — required for IRSA
# ---------------------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Managed node group
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size_gb

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "role" = "rideflow-workers"
  }

  # Cluster Autoscaler auto-discovery tags (doc §7.1 / Phase 2 step 2).
  # NOTE: aws_eks_node_group does not propagate these onto the underlying
  # ASG tags with the `k8s.io/cluster-autoscaler/...` = true value semantics
  # CA expects (it needs the *literal string* "true"/"owned" or the key's
  # mere presence); EKS managed node groups already tag the ASG with
  # k8s.io/cluster-autoscaler/<cluster-name> = owned and
  # k8s.io/cluster-autoscaler/enabled = true automatically. We tag the node
  # group resource itself for visibility/cost-allocation consistency.
  tags = merge(local.common_tags, {
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr_readonly,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------------
# IRSA — AWS Load Balancer Controller service account
# (namespace: platform, service account: aws-load-balancer-controller)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lb_controller_assume_role" {
  count = var.enable_lb_controller_irsa ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:platform:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  count              = var.enable_lb_controller_irsa ? 1 : 0
  name               = "${var.cluster_name}-lb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume_role[0].json
  tags               = local.common_tags
}

resource "aws_iam_policy" "lb_controller" {
  count       = var.enable_lb_controller_irsa ? 1 : 0
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "Least-privilege policy for the AWS Load Balancer Controller (upstream-published policy)."
  policy      = file("${path.module}/iam_policies/aws_load_balancer_controller.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  count      = var.enable_lb_controller_irsa ? 1 : 0
  role       = aws_iam_role.lb_controller[0].name
  policy_arn = aws_iam_policy.lb_controller[0].arn
}

# ---------------------------------------------------------------------------
# IRSA — Cluster Autoscaler service account
# (namespace: platform, service account: cluster-autoscaler)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  count = var.enable_cluster_autoscaler_irsa ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:platform:cluster-autoscaler"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  count              = var.enable_cluster_autoscaler_irsa ? 1 : 0
  name               = "${var.cluster_name}-cluster-autoscaler-irsa"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role[0].json
  tags               = local.common_tags
}

resource "aws_iam_policy" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler_irsa ? 1 : 0
  name        = "${var.cluster_name}-ClusterAutoscalerIAMPolicy"
  description = "Least-privilege policy for Cluster Autoscaler, scoped to ASGs tagged for this cluster."
  policy      = file("${path.module}/iam_policies/cluster_autoscaler.json")
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  count      = var.enable_cluster_autoscaler_irsa ? 1 : 0
  role       = aws_iam_role.cluster_autoscaler[0].name
  policy_arn = aws_iam_policy.cluster_autoscaler[0].arn
}
