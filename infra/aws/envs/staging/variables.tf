variable "aws_region" {
  description = "AWS region for staging resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Short project name used in AWS resource names."
  type        = string
  default     = "parago"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "staging"
}

variable "vpc_cidr" {
  description = "CIDR block for the isolated staging VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the NAT Gateway."
  type        = list(string)
  default     = ["10.42.0.0/24", "10.42.1.0/24"]
}

variable "app_subnet_cidr" {
  description = "Private subnet CIDR for the EC2 backend."
  type        = string
  default     = "10.42.10.0/24"
}

variable "cache_subnet_cidrs" {
  description = "Private subnet CIDRs for ElastiCache."
  type        = list(string)
  default     = ["10.42.20.0/24", "10.42.21.0/24"]
}

variable "instance_type" {
  description = "Initial staging EC2 size."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Encrypted EC2 root volume size."
  type        = number
  default     = 30
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS x86-64 AMI ID for ap-southeast-1."
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for staging."
  type        = string
  default     = "PriceClass_100"
}

variable "api_domain_name" {
  description = "Optional custom HTTPS hostname for the CloudFront API, such as api.sakaygaray.com."
  type        = string
  default     = ""
}

variable "api_certificate_validation_record_fqdns" {
  description = "DNS validation record FQDNs copied from the ACM certificate after adding them at the registrar."
  type        = list(string)
  default     = []
}

variable "enable_api_alias" {
  description = "Attach api_domain_name as a CloudFront alias after the certificate and any domain conflict are ready."
  type        = bool
  default     = true
}

variable "origin_header_value" {
  description = "Non-secret marker sent by CloudFront to Nginx for staging origin checks."
  type        = string
  default     = "parago-aws-staging-v1"
}

variable "secret_path_prefix" {
  description = "SSM Parameter Store path prefix for runtime secrets."
  type        = string
  default     = "/parago/staging/aws/v1"
}

variable "allowed_admin_cidr_blocks" {
  description = "Optional workstation CIDRs for temporary testing endpoints. SSH remains disabled."
  type        = list(string)
  default     = []
}
