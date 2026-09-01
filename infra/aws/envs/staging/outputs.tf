output "cloudfront_domain_name" {
  description = "Generated HTTPS hostname for AWS staging."
  value       = aws_cloudfront_distribution.api.domain_name
}

output "api_certificate_validation_options" {
  description = "Add these ACM DNS validation records at Namecheap before enabling the custom API domain."
  value = var.api_domain_name == "" ? [] : [
    for option in aws_acm_certificate.api[0].domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ]
}

output "api_custom_domain" {
  description = "Custom API hostname when certificate validation is complete."
  value       = local.custom_api_domain_enabled ? "https://${var.api_domain_name}/api/v1" : ""
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

output "driver_documents_bucket_name" {
  description = "Persistent private S3 bucket used for driver license documents."
  value       = local.driver_documents_bucket_name
}
