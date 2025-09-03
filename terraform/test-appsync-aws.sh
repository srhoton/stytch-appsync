#!/bin/bash

# Get JWT
if [ ! -f ~/git/tmp/jwt_file ]; then
    echo "JWT file not found. Run get-stytch-jwt.js first."
    exit 1
fi

JWT=$(cat ~/git/tmp/jwt_file | tr -d '\n')

echo "Testing AppSync with AWS CLI"
echo "============================"
echo ""

# Create GraphQL query file
cat > /tmp/appsync-query.json << EOF
{
  "query": "query CheckAuth { checkAuth { status message timestamp user { sub email organizationId sessionId roles context } } }"
}
EOF

echo "Sending GraphQL query to AppSync..."
echo ""

# Note: AWS CLI doesn't have direct AppSync query support, so we need to use curl with AWS Signature
# For Lambda auth, we can use a simple HTTP request

API_URL="https://fynthyrhcvbnzlwdfn23xjeuim.appsync-api.us-west-2.amazonaws.com/graphql"

# Try with x-api-key header (sometimes required for Lambda auth)
echo "Testing with x-api-key header:"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $JWT" \
  -d @/tmp/appsync-query.json | python3 -m json.tool

echo ""
echo "Testing with authorization header (lowercase):"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "authorization: $JWT" \
  -d @/tmp/appsync-query.json | python3 -m json.tool