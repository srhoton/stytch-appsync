# Local variables
locals {
  common_tags = merge(
    {
      Project     = var.api_name
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.tags
  )
}

# CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync" {
  name              = "/aws/appsync/apis/${var.api_name}"
  retention_in_days = 7
  tags              = local.common_tags
}

# IAM role for AppSync
resource "aws_iam_role" "appsync" {
  name = "${var.api_name}-appsync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudWatch logging - Restricted to specific log groups
resource "aws_iam_role_policy" "appsync_logging" {
  name = "${var.api_name}-logging-policy"
  role = aws_iam_role.appsync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.appsync.arn}",
          "${aws_cloudwatch_log_group.appsync.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/appsync/*"
        ]
      }
    ]
  })
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "api" {
  name                = var.api_name
  authentication_type = "AWS_LAMBDA"

  lambda_authorizer_config {
    authorizer_uri                   = aws_lambda_function.appsync_authorizer.arn
    authorizer_result_ttl_in_seconds = 0    # No caching for testing
    identity_validation_expression   = ".*" # Accept any token format
  }

  schema = file("${path.module}/schema.graphql")

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync.arn
    field_log_level          = "ALL"
    exclude_verbose_content  = false
  }

  xray_enabled = true

  tags = local.common_tags
}

# Data source for the resolver (NONE type - no backend required)
resource "aws_appsync_datasource" "none" {
  api_id = aws_appsync_graphql_api.api.id
  name   = "NoneDataSource"
  type   = "NONE"
}

# Resolver for checkAuth query
resource "aws_appsync_resolver" "check_auth" {
  api_id      = aws_appsync_graphql_api.api.id
  type        = "Query"
  field       = "checkAuth"
  data_source = aws_appsync_datasource.none.name

  request_template = <<EOF
{
  "version": "2017-02-28",
  "payload": {
    "identity": $util.toJson($context.identity),
    "requestId": "$context.requestId",
    "timestamp": "$util.time.nowISO8601()"
  }
}
EOF

  response_template = <<EOF
#set($ctx = $context.identity.resolverContext)
$util.toJson({
  "status": "success",
  "message": "Authentication successful",
  "timestamp": $util.time.nowISO8601(),
  "user": {
    "sub": $ctx.userId,
    "email": $ctx.email,
    "organizationId": $ctx.organizationId,
    "sessionId": $ctx.sessionId,
    "roles": $util.parseJson($ctx.roles),
    "context": $util.toJson($ctx)
  }
})
EOF
}