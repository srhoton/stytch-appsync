#!/bin/bash

echo "Testing AppSync Lambda Authorizer"
echo "=================================="
echo ""

# Get JWT from file
if [ ! -f ~/git/tmp/jwt_file ]; then
    echo "JWT file not found. Run get-stytch-jwt.js first."
    exit 1
fi

JWT=$(cat ~/git/tmp/jwt_file | tr -d '\n')

# Create test event
cat > /tmp/appsync-test-event.json << EOF
{
  "authorizationToken": "$JWT",
  "requestContext": {
    "apiId": "ra6userwn5curio5spygv74xeu",
    "accountId": "345594586248",
    "requestId": "test-request-id",
    "queryString": "query { checkAuth { status } }",
    "operationName": "CheckAuth",
    "variables": {}
  }
}
EOF

echo "Invoking Lambda function: stytch-appsync-appsync-authorizer"
echo ""

# Invoke Lambda
aws lambda invoke \
    --function-name stytch-appsync-appsync-authorizer \
    --payload file:///tmp/appsync-test-event.json \
    /tmp/appsync-lambda-result.json \
    --cli-binary-format raw-in-base64-out \
    --region us-west-2

echo ""
echo "Lambda Response:"
cat /tmp/appsync-lambda-result.json | python3 -m json.tool