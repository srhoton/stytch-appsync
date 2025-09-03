# Lambda function for AppSync custom authorizer
resource "aws_lambda_function" "appsync_authorizer" {
  function_name = "${var.api_name}-appsync-authorizer"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.appsync_lambda_authorizer_exec.arn
  timeout       = 10

  # Using zip file created by archive_file
  filename         = data.archive_file.appsync_authorizer_zip.output_path
  source_code_hash = data.archive_file.appsync_authorizer_zip.output_base64sha256

  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.stytch_credentials.name
      REGION      = data.aws_region.current.name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.api_name}-appsync-authorizer"
    }
  )
}

# Create Lambda deployment package for AppSync authorizer
# Using a local directory to manage dependencies
resource "null_resource" "appsync_authorizer_npm" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/lambda-authorizer-build
      mkdir -p ${path.module}/lambda-authorizer-build
      cat > ${path.module}/lambda-authorizer-build/package.json <<EOF
      {
        "name": "appsync-lambda-authorizer",
        "version": "1.0.0",
        "description": "Lambda authorizer for AppSync with Stytch B2B JWT verification",
        "main": "index.js",
        "dependencies": {
          "jose": "^5.2.0"
        }
      }
      EOF
      cat > ${path.module}/lambda-authorizer-build/index.js <<'EOF'
      const { createRemoteJWKSet, jwtVerify } = require('jose');
      const AWS = require('aws-sdk');
      
      // Initialize AWS SDK
      const secretsManager = new AWS.SecretsManager({ region: process.env.REGION });
      
      // Cache for secrets and JWKS
      let cachedSecrets = null;
      let secretsExpiry = null;
      let jwks = null;
      
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
        console.log('AppSync Lambda Authorizer invoked');
        console.log('Request context:', JSON.stringify(event.requestContext, null, 2));
        
        const { authorizationToken } = event;
        
        // Check if token is provided
        if (!authorizationToken) {
          console.log('No authorization token provided');
          return {
            isAuthorized: false
          };
        }
        
        try {
          // Get secrets from Secrets Manager
          const secrets = await getSecrets();
          
          // Initialize JWKS client if not already done
          if (!jwks) {
            const jwksUrl = 'https://test.stytch.com/v1/b2b/sessions/jwks/' + secrets.project_id;
            jwks = createRemoteJWKSet(new URL(jwksUrl));
          }
          
          // Remove Bearer prefix if present
          const token = authorizationToken.replace(/^Bearer\s+/i, '').trim();
          
          // Verify JWT with jose
          const { payload } = await jwtVerify(token, jwks, {
            issuer: secrets.issuer,
            audience: secrets.audience
          });
          
          console.log('JWT verified successfully for subject:', payload.sub);
          
          // Extract Stytch claims
          const orgClaim = payload['https://stytch.com/organization'] || {};
          const sessionClaim = payload['https://stytch.com/session'] || {};
          
          // Build response for AppSync
          // Note: resolverContext must be a map of string to string
          const response = {
            isAuthorized: true,
            resolverContext: {
              userId: payload.sub || '',
              organizationId: orgClaim.organization_id || '',
              organizationSlug: orgClaim.slug || '',
              sessionId: sessionClaim.id || '',
              email: payload.email || '',
              roles: JSON.stringify(sessionClaim.roles || []),
              accountId: payload.accountId || orgClaim.organization_id || '',
              iat: String(payload.iat || 0),
              exp: String(payload.exp || 0)
            },
            deniedFields: [],
            ttlOverride: 300 // Cache for 5 minutes
          };
          
          console.log('Authorization successful for user:', response.resolverContext.userId);
          console.log('Resolver context:', JSON.stringify(response.resolverContext, null, 2));
          
          return response;
          
        } catch (error) {
          console.error('JWT verification failed:', error.message);
          
          // Log specific error types for debugging
          if (error.code === 'ERR_JWT_EXPIRED') {
            console.error('Token has expired');
          } else if (error.code === 'ERR_JWT_CLAIM_VALIDATION_FAILED') {
            console.error('JWT claim validation failed');
          } else if (error.code === 'ERR_JWS_SIGNATURE_VERIFICATION_FAILED') {
            console.error('JWT signature verification failed');
          }
          
          return {
            isAuthorized: false
          };
        }
      };
      EOF
      cd ${path.module}/lambda-authorizer-build && npm install
    EOT
  }
}

data "archive_file" "appsync_authorizer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-authorizer-build"
  output_path = "${path.module}/appsync_lambda_authorizer.zip"

  depends_on = [null_resource.appsync_authorizer_npm]
}

# Lambda execution role for AppSync authorizer
resource "aws_iam_role" "appsync_lambda_authorizer_exec" {
  name = "${var.api_name}-appsync-lambda-auth-role"

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
resource "aws_iam_role_policy_attachment" "appsync_lambda_authorizer_exec_policy" {
  role       = aws_iam_role.appsync_lambda_authorizer_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for Lambda to read from Secrets Manager
resource "aws_iam_role_policy" "appsync_lambda_authorizer_secrets" {
  name = "${var.api_name}-appsync-lambda-auth-secrets-policy"
  role = aws_iam_role.appsync_lambda_authorizer_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.stytch_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Lambda permission for AppSync to invoke authorizer
resource "aws_lambda_permission" "appsync_authorizer_invoke" {
  statement_id  = "AllowAppSyncInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.appsync_authorizer.function_name
  principal     = "appsync.amazonaws.com"
  # Removed source_arn to fix BadRequestException issue
  # See: https://github.com/aws/aws-cdk/issues/19239#issuecomment-1065043013
}

# Outputs for AppSync Lambda authorizer
output "appsync_lambda_authorizer_function_name" {
  description = "AppSync Lambda authorizer function name"
  value       = aws_lambda_function.appsync_authorizer.function_name
}

output "appsync_lambda_authorizer_arn" {
  description = "AppSync Lambda authorizer ARN"
  value       = aws_lambda_function.appsync_authorizer.arn
}