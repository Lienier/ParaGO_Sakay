output "cloudfront_domain_name" {
  description = "Generated HTTPS hostname for AWS staging."
  value       = aws_cloudfront_distribution.api.domain_name
}

output "nat_eip" {
  description = "Allowlist this IP in the staging Atlas project only."
  value       = aws_eip.nat.public_ip
}

output "ec2_instance_id" {
  description = "Use Session Manager against this private instance."
  value       = aws_instance.api.id
}

output "redis_endpoint" {
  description = "Private Valkey primary endpoint. Auth token is in SSM."
  value       = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "redis_namespace" {
  description = "Staging Redis namespace for runtime env."
  value       = "parago:staging:aws:v1"
}
