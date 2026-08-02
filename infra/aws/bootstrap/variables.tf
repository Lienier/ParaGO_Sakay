variable "aws_region" {
  description = "AWS region for Terraform state storage."
  type        = string
  default     = "ap-southeast-1"
}

variable "state_bucket_name" {
  description = "Optional globally unique S3 bucket name for Terraform state."
  type        = string
  default     = null
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to deploy AWS staging through OIDC."
  type        = string
  default     = "Lienier/ParaGO_Sakay"
}
