# infra/envs/primary — ap-south-1 (Mumbai)
#
# Root module instantiating vpc + eks + redis + data for the primary
# region, plus bootstrapping the `platform` namespace and the platform
# controllers (AWS Load Balancer Controller, Cluster Autoscaler,
# metrics-server) via Helm, per doc §7.1 / §11 Phase 2 step 3.
#
# Apply order: infra/global first (creates ECR repos this cluster will
# pull from and the IAM OIDC trust for CI), then this root module. See
# infra/README.md.

module "vpc" {
  source = "../../modules/vpc"

  region       = var.region
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs

  tags = { Region = "primary" }
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids

  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size
  node_capacity_type  = var.node_capacity_type

  tags = { Region = "primary" }
}

module "redis" {
  source = "../../modules/redis"

  cluster_name               = var.cluster_name
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = { Region = "primary" }
}

# Owns the single creation of the DynamoDB Global Tables — see
# infra/modules/data/main.tf header comment. infra/envs/secondary does NOT
# instantiate this module.
module "data" {
  source = "../../modules/data"

  table_name_prefix = "rideflow"
  replica_regions    = var.dynamodb_replica_regions

  tags = { Region = "primary" }
}

# ---------------------------------------------------------------------------
# Platform namespace + controllers (doc §7.2 `platform` namespace contents)
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
    labels = {
      "app.kubernetes.io/part-of" = "rideflow"
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = kubernetes_namespace.platform.metadata[0].name
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lb_controller_irsa_role_arn
  }

  depends_on = [module.eks]
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = kubernetes_namespace.platform.metadata[0].name
  version    = "9.37.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.cluster_autoscaler_irsa_role_arn
  }
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [module.eks]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  namespace  = kubernetes_namespace.platform.metadata[0].name
  version    = "3.12.1"

  depends_on = [module.eks]
}
