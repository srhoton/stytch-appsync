# API Gateway v2 (HTTP API) with JWT Authorization

# API Gateway v2
resource "aws_apigatewayv2_api" "http_api" {
  name                         = "${var.api_name}-http-api"
  protocol_type                = "HTTP"
  description                  = "HTTP API with JWT authorization for Stytch OIDC"
  disable_execute_api_endpoint = false

  tags = merge(
    local.common_tags,
    {
      Name = "${var.api_name}-http-api"
      Type = "HTTP"
    }
  )
}

# JWT Authorizer
resource "aws_apigatewayv2_authorizer" "jwt_auth" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.api_name}-jwt-authorizer"

  jwt_configuration {
    issuer   = "https://gaudy-barracuda-8765.customers.stytch.dev"
    audience = ["connected-app-test-bffc3f84-7a10-4a82-b372-62b45a517c2b"]
  }
}

# Lambda function for simple success response
resource "aws_lambda_function" "auth_success" {
  function_name = "${var.api_name}-auth-success"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 10

  # Using zip file created by archive_file
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      API_NAME = var.api_name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.api_name}-auth-success"
    }
  )
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-EOT
      exports.handler = async (event) => {
        console.log('Event:', JSON.stringify(event, null, 2));
        
        // Extract JWT claims from the authorizer context
        const claims = event.requestContext?.authorizer?.jwt?.claims || {};
        
        return {
          statusCode: 200,
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            status: 'success',
            message: 'Authentication successful',
            timestamp: new Date().toISOString(),
            user: {
              sub: claims.sub || 'unknown',
              email: claims.email || null,
              claims: claims
            }
          })
        };
      };
    EOT
    filename = "index.js"
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_exec" {
  name = "${var.api_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda permission for API Gateway - Restricted to specific routes
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_success.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/${aws_apigatewayv2_route.verify.route_key}"
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth_success.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# API Gateway route with authorization
resource "aws_apigatewayv2_route" "verify" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /verify"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_auth.id
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "dev"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = false
    throttling_rate_limit    = 100
    throttling_burst_limit   = 200
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      requestTime     = "$context.requestTime"
      protocol        = "$context.protocol"
      httpMethod      = "$context.httpMethod"
      path            = "$context.path"
      status          = "$context.status"
      responseLength  = "$context.responseLength"
      errorMessage    = "$context.error.message"
      authorizerError = "$context.authorizer.error"
      integration     = "$context.integration.status"
    })
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.api_name}-dev-stage"
      Environment = "dev"
    }
  )
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigatewayv2/${var.api_name}-http-api"
  retention_in_days = 7

  tags = local.common_tags
}