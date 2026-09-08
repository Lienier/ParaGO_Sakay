# This identity is persistent: do not destroy it during routine staging teardown.
resource "aws_sesv2_email_identity" "auth" {
  email_identity = "sakaygaray.com"
  lifecycle {
    prevent_destroy = true
  }
}

output "auth_email_dkim_tokens" {
  description = "Publish each token as token._domainkey.sakaygaray.com CNAME token.dkim.amazonses.com."
  value       = aws_sesv2_email_identity.auth.dkim_signing_attributes[0].tokens
}
