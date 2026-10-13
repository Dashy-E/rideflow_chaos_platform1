output "redis_endpoint" {
  value = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.this.port
}

output "redis_url" {
  description = "Full REDIS_URL env var value (doc contracts.md)."
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.port}"
}

output "security_group_id" {
  value = aws_security_group.redis.id
}
