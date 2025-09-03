#!/usr/bin/env node

const http = require('http');
const https = require('https');
const crypto = require('crypto');
const fs = require('fs');
const { URL, URLSearchParams } = require('url');

// Configuration
const CONFIG = {
  clientId: 'connected-app-test-bffc3f84-7a10-4a82-b372-62b45a517c2b',
  clientSecret: 'xQP6VGRzkov_5_ML4K6fe3chztf91S9ihXicK6EGwoJnxadu',
  issuer: 'https://gaudy-barracuda-8765.customers.stytch.dev',
  redirectUri: 'http://localhost:8080/callback',
  organizationId: 'organization-test-3e306a42-6537-41f3-80f4-a1d6e16f56f0',
  memberEmail: 'steve.rhoton@fullbay.com',
  port: 8080
};

// PKCE helpers
function base64URLEncode(str) {
  return str.toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function generateCodeVerifier() {
  return base64URLEncode(crypto.randomBytes(32));
}

function generateCodeChallenge(verifier) {
  return base64URLEncode(crypto.createHash('sha256').update(verifier).digest());
}

// Generate random state
function generateState() {
  return base64URLEncode(crypto.randomBytes(16));
}

// Make HTTPS request
function makeRequest(url, method = 'GET', headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method,
      headers
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            resolve(data);
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(body);
    }
    req.end();
  });
}

// Start local server to handle OAuth callback
function startCallbackServer(state, codeVerifier) {
  return new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, `http://localhost:${CONFIG.port}`);
      
      if (url.pathname === '/callback') {
        const code = url.searchParams.get('code');
        const returnedState = url.searchParams.get('state');
        const error = url.searchParams.get('error');
        
        if (error) {
          res.writeHead(400, { 'Content-Type': 'text/html' });
          res.end(`<html><body><h1>Error</h1><p>${error}: ${url.searchParams.get('error_description')}</p></body></html>`);
          server.close();
          reject(new Error(`OAuth error: ${error}`));
          return;
        }
        
        if (returnedState !== state) {
          res.writeHead(400, { 'Content-Type': 'text/html' });
          res.end('<html><body><h1>Error</h1><p>Invalid state parameter</p></body></html>');
          server.close();
          reject(new Error('Invalid state parameter'));
          return;
        }
        
        if (code) {
          res.writeHead(200, { 'Content-Type': 'text/html' });
          res.end(`
            <html>
            <body>
              <h1>Authorization Successful!</h1>
              <p>Authorization code received. Exchanging for tokens...</p>
              <p>You can close this window.</p>
            </body>
            </html>
          `);
          
          server.close();
          
          try {
            // Exchange code for tokens
            const tokens = await exchangeCodeForTokens(code, codeVerifier);
            resolve(tokens);
          } catch (err) {
            reject(err);
          }
        }
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not found');
      }
    });
    
    server.listen(CONFIG.port, () => {
      console.log(`\nCallback server listening on http://localhost:${CONFIG.port}`);
    });
    
    // Timeout after 5 minutes
    setTimeout(() => {
      server.close();
      reject(new Error('Timeout waiting for authorization'));
    }, 300000);
  });
}

// Exchange authorization code for tokens
async function exchangeCodeForTokens(code, codeVerifier) {
  console.log('\n📝 Exchanging authorization code for tokens...');
  
  const tokenEndpoint = `${CONFIG.issuer}/v1/oauth2/token`;
  
  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: CONFIG.clientId,
    client_secret: CONFIG.clientSecret,
    code: code,
    redirect_uri: CONFIG.redirectUri,
    code_verifier: codeVerifier
  });
  
  const response = await makeRequest(
    tokenEndpoint,
    'POST',
    {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json'
    },
    params.toString()
  );
  
  console.log('\n✅ Tokens received successfully!');
  
  if (response.access_token) {
    // Save JWT to file
    fs.writeFileSync('/Users/steverhoton/git/tmp/jwt_file', response.access_token);
    console.log('Access token saved to ~/git/tmp/jwt_file');
    
    // Decode and display token info
    const parts = response.access_token.split('.');
    if (parts.length === 3) {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
      console.log('\nAccess Token Claims:');
      console.log('  Issuer:', payload.iss);
      console.log('  Subject:', payload.sub);
      console.log('  Audience:', JSON.stringify(payload.aud));
      console.log('  Expires:', new Date(payload.exp * 1000).toISOString());
    }
  }
  
  if (response.id_token) {
    // Save ID token
    fs.writeFileSync('/Users/steverhoton/git/tmp/id_token', response.id_token);
    console.log('\nID token saved to ~/git/tmp/id_token');
    
    // Decode and display ID token info
    const parts = response.id_token.split('.');
    if (parts.length === 3) {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
      console.log('\nID Token Claims:');
      console.log('  Issuer:', payload.iss);
      console.log('  Subject:', payload.sub);
      console.log('  Audience:', JSON.stringify(payload.aud));
      console.log('  Email:', payload.email);
    }
  }
  
  return response;
}

// Main OAuth flow
async function startOAuthFlow() {
  console.log('🚀 Starting Stytch Connected App OAuth Flow\n');
  console.log('Configuration:');
  console.log('  Client ID:', CONFIG.clientId);
  console.log('  Issuer:', CONFIG.issuer);
  console.log('  Redirect URI:', CONFIG.redirectUri);
  
  // Generate PKCE parameters
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = generateCodeChallenge(codeVerifier);
  const state = generateState();
  
  // Start callback server
  const serverPromise = startCallbackServer(state, codeVerifier);
  
  // Build authorization URL
  const authEndpoint = `${CONFIG.issuer}/auth/authenticate`;
  const authParams = new URLSearchParams({
    client_id: CONFIG.clientId,
    response_type: 'code',
    redirect_uri: CONFIG.redirectUri,
    scope: 'openid email profile',
    state: state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
    organization_id: CONFIG.organizationId,
    login_hint: CONFIG.memberEmail
  });
  
  const authUrl = `${authEndpoint}?${authParams.toString()}`;
  
  console.log('\n🔗 Authorization URL:');
  console.log(authUrl);
  console.log('\n👆 Please open this URL in your browser to authenticate');
  console.log('   Or run: open "' + authUrl + '"');
  
  // Also try to open the browser automatically
  const { exec } = require('child_process');
  exec(`open "${authUrl}"`, (err) => {
    if (err) {
      console.log('\n⚠️  Could not open browser automatically. Please copy and paste the URL above.');
    }
  });
  
  try {
    const tokens = await serverPromise;
    console.log('\n🎉 OAuth flow completed successfully!');
    console.log('\n📊 Token Summary:');
    console.log('  Access Token: Saved to ~/git/tmp/jwt_file');
    if (tokens.id_token) {
      console.log('  ID Token: Saved to ~/git/tmp/id_token');
    }
    console.log('  Token Type:', tokens.token_type);
    console.log('  Expires In:', tokens.expires_in, 'seconds');
    
    return tokens;
  } catch (error) {
    console.error('\n❌ OAuth flow failed:', error.message);
    throw error;
  }
}

// Run the OAuth flow
if (require.main === module) {
  startOAuthFlow()
    .then(() => {
      console.log('\n✨ Done! You can now test the API Gateway with the obtained token.');
      process.exit(0);
    })
    .catch((error) => {
      console.error('\n💥 Fatal error:', error);
      process.exit(1);
    });
}