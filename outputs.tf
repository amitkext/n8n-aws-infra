output "n8n_url" {
  description = "The URL of the n8n instance"
  value       = "https://${var.domain_name}"
}

output "database_endpoint" {
  description = "The RDS PostgreSQL endpoint"
  value       = module.rds.db_instance_address
  sensitive   = true
}

output "redis_endpoint" {
  description = "The ElastiCache Redis endpoint"
  value       = module.redis.redis_endpoint_address
  sensitive   = true
}