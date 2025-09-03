# Secrets Manager for Stytch credentials
resource "aws_secretsmanager_secret" "stytch_credentials" {
  name                    = "${var.api_name}-stytch-credentials"
  description             = "Stytch B2B API credentials for ${var.api_name}"
  recovery_window_in_days = 7 # Allows recovery if accidentally deleted

  tags = merge(
    local.common_tags,
    {
      Name = "${var.api_name}-stytch-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "stytch_credentials" {
  secret_id = aws_secretsmanager_secret.stytch_credentials.id
  secret_string = jsonencode({
    project_id = var.stytch_project_id
    issuer     = "stytch.com/${var.stytch_project_id}"
    audience   = var.stytch_project_id
  })
}

# Output the secret ARN for reference
output "stytch_credentials_secret_arn" {
  description = "ARN of the Stytch credentials secret"
  value       = aws_secretsmanager_secret.stytch_credentials.arn
}