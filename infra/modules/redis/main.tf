# infra/modules/redis
#
# ElastiCache subnet group + single-node Redis cluster (cache.t4g.micro,
# cluster-mode off), used by driver-service for the GEO index (doc §6.5).

locals {
  common_tags = merge(var.tags, {
    "Project" = "rideflow"
    "Module"  = "redis"
  })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.cluster_name}-redis-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = local.common_tags
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-redis-"
  description = "Allow Redis (6379) from EKS worker nodes only."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress_redis" {
  count                    = length(var.allowed_security_group_ids)
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = var.allowed_security_group_ids[count.index]
  description               = "Redis from EKS node SG"
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.redis.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.cluster_name}-redis"
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  apply_immediately = true

  tags = local.common_tags
}
