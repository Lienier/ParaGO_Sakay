terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.43" }
  }
}

provider "aws" { region = "ap-southeast-1" }
provider "aws" {
  alias  = "certificate"
  region = "us-east-1"
}
variable "certificate_ready" {
  type    = bool
  default = false
}
data "aws_caller_identity" "current" {}
locals {
  domain = "downloads.sakaygaray.com"
  bucket = "sakaygaray-downloads-${data.aws_caller_identity.current.account_id}"
}
resource "aws_acm_certificate" "downloads" {
  provider          = aws.certificate
  domain_name       = local.domain
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "aws_s3_bucket" "downloads" {
  bucket = local.bucket
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "downloads" {
  bucket                  = aws_s3_bucket.downloads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_cloudfront_origin_access_control" "downloads" {
  name                              = "sakaygaray-downloads"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_response_headers_policy" "downloads" {
  name = "sakaygaray-download-security"
  security_headers_config {
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src https://api.sakaygaray.com; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
      override                = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
  }
}
resource "aws_cloudfront_distribution" "downloads" {
  lifecycle { prevent_destroy = true }
  count               = var.certificate_ready ? 1 : 0
  enabled             = true
  aliases             = [local.domain]
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  origin {
    domain_name              = aws_s3_bucket.downloads.bucket_regional_domain_name
    origin_id                = "private-downloads"
    origin_access_control_id = aws_cloudfront_origin_access_control.downloads.id
  }
  default_cache_behavior {
    target_origin_id           = "private-downloads"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    min_ttl                    = 0
    default_ttl                = 60
    max_ttl                    = 31536000
    response_headers_policy_id = aws_cloudfront_response_headers_policy.downloads.id
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.downloads.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}
resource "aws_s3_bucket_policy" "downloads" {
  bucket = aws_s3_bucket.downloads.id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([
    { Sid      = "RequireTLS", Effect = "Deny", Principal = "*", Action = "s3:*",
      Resource = [aws_s3_bucket.downloads.arn, "${aws_s3_bucket.downloads.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } } },
    { Sid      = "ImmutableReleaseObjects", Effect = "Deny", Principal = "*", Action = "s3:PutObject",
      Resource = "${aws_s3_bucket.downloads.arn}/releases/*",
    Condition = { Null = { "s3:if-none-match" = "true" } } }
    ], var.certificate_ready ? [
    { Sid    = "CloudFrontReadsOnly", Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" },
      Action = "s3:GetObject", Resource = "${aws_s3_bucket.downloads.arn}/*",
    Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.downloads[0].arn } } }
  ] : []) })
}
resource "aws_iam_policy" "uploader" {
  name = "sakaygaray-local-apk-uploader"
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.downloads.arn}/releases/*" }
  ] })
}
resource "aws_s3_object" "page" {
  for_each      = { "index.html" = "text/html", "downloads.js" = "application/javascript", "downloads.css" = "text/css" }
  bucket        = aws_s3_bucket.downloads.id
  key           = each.key
  source        = "${path.module}/../../downloads/${each.key}"
  source_hash   = filemd5("${path.module}/../../downloads/${each.key}")
  content_type  = each.value
  cache_control = "public,max-age=60"
}
output "certificate_dns_records" { value = aws_acm_certificate.downloads.domain_validation_options }
output "download_cname_target" { value = try(aws_cloudfront_distribution.downloads[0].domain_name, "Validate certificate, then apply with certificate_ready=true") }
output "uploader_policy_arn" { value = aws_iam_policy.uploader.arn }
output "local_uploader_configuration" {
  value = { bucket = local.bucket, region = "ap-southeast-1", origin = "https://${local.domain}" }
}
