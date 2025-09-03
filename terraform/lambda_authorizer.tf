# Lambda function for custom authorizer
resource "aws_lambda_function" "custom_authorizer" {
  function_name = "${var.api_name}-custom-authorizer"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_authorizer_exec.arn
  timeout       = 10

  # Using zip file created by archive_file
  filename         = data.archive_file.authorizer_zip.output_path
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.stytch_credentials.name
      REGION      = data.aws_region.current.name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.api_name}-custom-authorizer"
    }
  )
}

# Create Lambda deployment package for authorizer
data "archive_file" "authorizer_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_authorizer.zip"

  source {
    content  = <<-EOT
      const AWS = require('aws-sdk');
      const secretsManager = new AWS.SecretsManager({ region: process.env.REGION });
      
      // Cache for secrets
      let cachedSecrets = null;
      let secretsExpiry = null;
      
      // Function to get secrets from Secrets Manager
      async function getSecrets() {
        const now = Date.now();
        
        // Return cached secrets if still valid (5 minute cache)
        if (cachedSecrets && secretsExpiry && now < secretsExpiry) {
          return cachedSecrets;
        }
        
        try {
          const data = await secretsManager.getSecretValue({ SecretId: process.env.SECRET_NAME }).promise();
          cachedSecrets = JSON.parse(data.SecretString);
          secretsExpiry = now + (5 * 60 * 1000); // Cache for 5 minutes
          return cachedSecrets;
        } catch (error) {
          console.error('Failed to retrieve secrets:', error);
          throw new Error('Unable to retrieve configuration');
        }
      }
      
      exports.handler = async (event) => {
        console.log('Authorizer Event:', JSON.stringify(event, null, 2));
        
        try {
          // Get secrets from Secrets Manager
          const secrets = await getSecrets();
          
          // Extract token from authorization header or identity source
          const authHeader = event.headers?.authorization || event.headers?.Authorization;
          const identitySource = event.identitySource?.[0];
          const token = authHeader || identitySource;
          
          console.log('Auth header:', authHeader ? 'present' : 'missing');
          console.log('Identity source:', identitySource ? 'present' : 'missing');
          
          if (!token) {
            console.log('No authorization token provided');
            return { isAuthorized: false };
          }
          
          // Remove 'Bearer ' prefix if present
          const jwt = token.replace(/^Bearer\s+/i, '');
          console.log('JWT length:', jwt.length);
          console.log('JWT parts:', jwt.split('.').length);
          
          // Decode JWT (basic validation - in production, verify signature)
          const parts = jwt.split('.');
          if (parts.length !== 3) {
            console.log('Invalid JWT format - expected 3 parts, got', parts.length);
            console.log('First 50 chars of token:', jwt.substring(0, 50));
            return { isAuthorized: false };
          }
          
          // Decode payload
          const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
          
          console.log('JWT Payload:', JSON.stringify(payload, null, 2));
          
          // Validate issuer
          if (payload.iss !== secrets.issuer) {
            console.log('Invalid issuer:', payload.iss);
            return { isAuthorized: false };
          }
          
          // Validate audience
          const audience = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
          if (!audience.includes(secrets.audience)) {
            console.log('Invalid audience:', payload.aud);
            return { isAuthorized: false };
          }
          
          // Check expiration
          const now = Math.floor(Date.now() / 1000);
          if (payload.exp && payload.exp < now) {
            console.log('Token expired');
            return { isAuthorized: false };
          }
          
          // Validate organization if present and configured in secrets
          const orgClaim = payload['https://stytch.com/organization'];
          if (secrets.organization_id && orgClaim && orgClaim.organization_id !== secrets.organization_id) {
            console.log('Invalid organization:', orgClaim.organization_id);
            return { isAuthorized: false };
          }
          
          // Generate Allow response for simple response format
          console.log('Authorization successful for:', payload.sub);
          return {
            isAuthorized: true,
            context: {
              sub: payload.sub || '',
              organizationId: orgClaim?.organization_id || '',
              sessionId: payload['https://stytch.com/session']?.id || '',
              email: payload.email || ''
            }
          };
          
        } catch (error) {
          console.error('Authorization error:', error);
          return {
            isAuthorized: false
          };
        }
      };
    EOT
    filename = "index.js"
  }
}

# Lambda execution role for authorizer
resource "aws_iam_role" "lambda_authorizer_exec" {
  name = "${var.api_name}-lambda-authorizer-exec-role"

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

# Attach basic execution policy to Lambda authorizer role
resource "aws_iam_role_policy_attachment" "lambda_authorizer_exec_policy" {
  role       = aws_iam_role.lambda_authorizer_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for Lambda to read Secrets Manager
resource "aws_iam_role_policy" "lambda_authorizer_secrets" {
  name = "${var.api_name}-lambda-authorizer-secrets-policy"
  role = aws_iam_role.lambda_authorizer_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.stytch_credentials.arn
      }
    ]
  })
}

# Lambda permission for API Gateway to invoke authorizer - Restricted to specific API
resource "aws_lambda_permission" "api_gateway_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custom_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.lambda_auth.id}"
}

# Custom authorizer for API Gateway
resource "aws_apigatewayv2_authorizer" "lambda_auth" {
  api_id                            = aws_apigatewayv2_api.http_api.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.custom_authorizer.invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${var.api_name}-lambda-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true

  authorizer_result_ttl_in_seconds = 0 # No caching for testing
}

# New route with Lambda authorizer
resource "aws_apigatewayv2_route" "verify_lambda_auth" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /verify-lambda"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda_auth.id
}

# Outputs for Lambda authorizer
output "lambda_authorizer_function_name" {
  description = "Lambda authorizer function name"
  value       = aws_lambda_function.custom_authorizer.function_name
}

output "api_gateway_verify_lambda_endpoint" {
  description = "Full URL for the /verify-lambda endpoint with Lambda authorizer"
  value       = "${aws_apigatewayv2_stage.dev.invoke_url}/verify-lambda"
}