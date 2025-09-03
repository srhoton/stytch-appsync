#!/bin/bash

API_URL="https://76umiwvx2m.execute-api.us-west-2.amazonaws.com/dev/verify-lambda"

echo "Testing API Gateway /verify-lambda endpoint with Lambda Authorizer"
echo "=================================================================="
echo ""

# Test without authorization
echo "1. Testing without authorization (expecting 401):"
curl -s "$API_URL" | python3 -m json.tool
echo ""

# Test with JWT if available
if [ -f ~/git/tmp/jwt_file ]; then
    echo "2. Testing with JWT token from file:"
    JWT=$(cat ~/git/tmp/jwt_file | tr -d '\n')
    curl -s -H "Authorization: Bearer $JWT" "$API_URL" | python3 -m json.tool
else
    echo "2. No JWT token file found at ~/git/tmp/jwt_file"
    echo "   To test with authorization, provide a valid JWT token."
fi