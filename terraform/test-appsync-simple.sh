#!/bin/bash

API_URL="https://fynthyrhcvbnzlwdfn23xjeuim.appsync-api.us-west-2.amazonaws.com/graphql"
QUERY='{"query":"query CheckAuth { checkAuth { status message timestamp user { sub email organizationId sessionId roles context } } }"}'

echo "Testing AppSync with simple authorization token"
echo "==============================================="
echo ""

echo "1. Testing with 'custom-authorized' token (should work):"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: custom-authorized" \
  -d "$QUERY" | python3 -m json.tool

echo ""
echo "2. Testing with lowercase 'authorization' header:"
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "authorization: custom-authorized" \
  -d "$QUERY" | python3 -m json.tool