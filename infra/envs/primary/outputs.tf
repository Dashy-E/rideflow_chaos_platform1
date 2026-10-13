output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "lb_controller_irsa_role_arn" {
  value = module.eks.lb_controller_irsa_role_arn
}

output "cluster_autoscaler_irsa_role_arn" {
  value = module.eks.cluster_autoscaler_irsa_role_arn
}

output "redis_url" {
  value = module.redis.redis_url
}

output "users_table_name" {
  value = module.data.users_table_name
}

output "rides_table_name" {
  value = module.data.rides_table_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
