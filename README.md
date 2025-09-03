# stytch-appsync
Demo repo to show auth through Stytch with AppSync

## 🚀 Quick Start

This project demonstrates OIDC authentication using Stytch Connected Apps with AWS AppSync.

### Infrastructure Status
- ✅ **Deployed to AWS us-west-2**
- ✅ **AppSync API**: `https://fynthyrhcvbnzlwdfn23xjeuim.appsync-api.us-west-2.amazonaws.com/graphql`
- ✅ **OIDC Configured**: Stytch issuer at `https://gaudy-barracuda-8765.customers.stytch.dev`
- ✅ **Terraform State**: Stored in S3 bucket `steve-rhoton-tfstate`

## 📋 Testing the Authentication

Based on the [Stytch Connected Apps documentation](https://stytch.com/docs/b2b/guides/connected-apps/getting-started/api), Connected Apps use the **OIDC Authorization Code flow** for user authentication.

### Option 1: Browser-Based Testing (Recommended)

```bash
# Start the OAuth server
node auth-server.js

# Open http://localhost:8080 in your browser
# Click "Start OAuth Flow" to begin authentication
```

### Option 2: Direct API Testing

If you have a valid JWT token from Stytch:

```bash
curl -X POST https://fynthyrhcvbnzlwdfn23xjeuim.appsync-api.us-west-2.amazonaws.com/graphql \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"query { checkAuth { status message timestamp user { sub email claims } } }"}'
```

### Option 3: Automated Test Script

```bash
node test-connected-app.js
```

## 🔑 Configuration

| Component | Value |
|-----------|--------|
| Client ID | `connected-app-test-bffc3f84-7a10-4a82-b372-62b45a517c2b` |
| Client Secret | Stored in `~/git/tmp/stytch_oidc_token` |
| OIDC Issuer | `https://gaudy-barracuda-8765.customers.stytch.dev` |
| User Credentials | Stored in `~/git/tmp/stytch.json` |

## 📝 Key Findings

1. **Authentication Type**: Connected Apps require user authentication via Authorization Code flow (not M2M/Client Credentials)
2. **OIDC Compliance**: The issuer provides proper `.well-known/openid-configuration` and JWKS endpoints
3. **Grant Types Supported**: `authorization_code`, `client_credentials`, `refresh_token` (but client_credentials is not authorized for this app)
4. **AppSync Integration**: Successfully validates JWT tokens from the Stytch issuer

## 🏗️ Infrastructure Management

```bash
cd terraform

# Deploy/Update
terraform apply

# Update client ID
terraform apply -var="oidc_client_id=NEW_CLIENT_ID"

# Destroy
terraform destroy
```
