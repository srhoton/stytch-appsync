variable "api_name" {
  description = "Name of the AppSync API"
  type        = string
  default     = "stytch-appsync"
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL for authentication"
  type        = string
  default     = "https://gaudy-barracuda-8765.customers.stytch.dev"

  validation {
    condition     = can(regex("^https://", var.oidc_issuer_url))
    error_message = "OIDC issuer URL must start with https://"
  }
}

variable "oidc_client_id" {
  description = "OIDC client ID for authentication (optional)"
  type        = string
  default     = "connected-app-test-bffc3f84-7a10-4a82-b372-62b45a517c2b"
}

variable "oidc_auth_ttl" {
  description = "Auth TTL in seconds for OIDC tokens"
  type        = number
  default     = 0
}

variable "oidc_iat_ttl" {
  description = "IAT TTL in seconds for OIDC tokens"
  type        = number
  default     = 0
}

variable "environment" {
  description = "Environment name (e.g., sandbox, dev, staging, prod)"
  type        = string
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: sandbox, dev, staging, prod"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "stytch_project_id" {
  description = "Stytch B2B Project ID"
  type        = string
  sensitive   = true
}

variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation for Stytch credentials"
  type        = bool
  default     = false
}