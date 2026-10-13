output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed shared security group (nodes + control plane). Used to authorize Redis ingress."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_role_arn" {
  value = aws_iam_role.node.arn
}

output "node_group_name" {
  value = aws_eks_node_group.default.node_group_name
}

output "lb_controller_irsa_role_arn" {
  description = "IAM role ARN to annotate the aws-load-balancer-controller ServiceAccount with (eks.amazonaws.com/role-arn)."
  value       = var.enable_lb_controller_irsa ? aws_iam_role.lb_controller[0].arn : null
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "IAM role ARN to annotate the cluster-autoscaler ServiceAccount with (eks.amazonaws.com/role-arn)."
  value       = var.enable_cluster_autoscaler_irsa ? aws_iam_role.cluster_autoscaler[0].arn : null
}
