output "hosted_zone_id" {
  value = module.dns.zone_id
}

output "hosted_zone_name_servers" {
  description = "Delegate your domain registrar's NS records to these."
  value       = module.dns.name_servers
}

output "github_actions_deploy_role_arn" {
  description = "Put this in the GitHub repo secret AWS_DEPLOY_ROLE (doc §11 Phase 6)."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}
