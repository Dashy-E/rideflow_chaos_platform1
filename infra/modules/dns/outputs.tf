output "zone_id" {
  value = local.zone_id
}

output "name_servers" {
  value = var.create_zone ? aws_route53_zone.this[0].name_servers : null
}

output "primary_health_check_id" {
  value = var.create_failover_records ? aws_route53_health_check.primary[0].id : null
}

output "secondary_health_check_id" {
  value = var.create_failover_records ? aws_route53_health_check.secondary[0].id : null
}

output "fqdn" {
  value = var.record_name
}
