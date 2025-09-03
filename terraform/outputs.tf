output "graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.id
}

output "graphql_api_url" {
  description = "The URL of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.uris["GRAPHQL"]
}

output "graphql_api_arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.arn
}

output "api_name" {
  description = "The name of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.api.name
}

output "oidc_issuer" {
  description = "The OIDC issuer URL configured for the API"
  value       = var.oidc_issuer_url
}

output "authentication_type" {
  description = "The authentication type configured for the API"
  value       = aws_appsync_graphql_api.api.authentication_type
}

output "cloudwatch_log_group" {
  description = "The CloudWatch log group for AppSync logs"
  value       = aws_cloudwatch_log_group.appsync.name
}

# API Gateway v2 Outputs
output "api_gateway_url" {
  description = "API Gateway HTTP API URL"
  value       = aws_apigatewayv2_stage.dev.invoke_url
}

output "api_gateway_verify_endpoint" {
  description = "Full URL for the /verify endpoint"
  value       = "${aws_apigatewayv2_stage.dev.invoke_url}/verify"
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.http_api.id
}

output "jwt_authorizer_id" {
  description = "JWT Authorizer ID"
  value       = aws_apigatewayv2_authorizer.jwt_auth.id
}

output "lambda_function_name" {
  description = "Lambda function name for auth success"
  value       = aws_lambda_function.auth_success.function_name
}