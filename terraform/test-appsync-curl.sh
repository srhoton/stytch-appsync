#!/bin/bash

API_URL="https://fynthyrhcvbnzlwdfn23xjeuim.appsync-api.us-west-2.amazonaws.com/graphql"
QUERY='{"query":"query CheckAuth { checkAuth { status message timestamp user { sub email organizationId sessionId roles context } } }"}'

echo "Testing AppSync GraphQL API with Lambda Authorizer using curl"
echo "=============================================================="
echo ""

# Get JWT
if [ ! -f ~/git/tmp/jwt_file ]; then
    echo "JWT file not found. Run get-stytch-jwt.js first."
    exit 1
fi

JWT=$(cat ~/git/tmp/jwt_file | tr -d '\n')

echo "1. Testing with 'Authorization: Bearer JWT' header:"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "$QUERY" | python3 -m json.tool

echo ""
echo "2. Testing with just 'Authorization: JWT' header (no Bearer):"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: $JWT" \
  -d "$QUERY" | python3 -m json.tool