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
