resource "random_password" "origin_header" {
  length  = 48
  special = false
}

resource "aws_iam_role_policy" "auth_email" {
  name = "${local.name_prefix}-auth-email"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail"]
        Resource = "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/sakaygaray.com"
        Condition = {
          StringEquals = { "ses:FromAddress" = "no-reply@sakaygaray.com" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ses:GetAccount"]
        Resource = "*"
      }
    ]
  })
}
