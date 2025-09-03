#!/bin/bash

echo "=== Terraform Validation Script ==="
echo ""

echo "1. Checking Terraform formatting..."
if terraform fmt -check; then
    echo "✅ Terraform formatting is correct"
else
    echo "❌ Terraform formatting issues found. Run 'terraform fmt' to fix."
    exit 1
fi

echo ""
echo "2. Initializing Terraform..."
if terraform init -backend=false > /dev/null 2>&1; then
    echo "✅ Terraform initialized successfully"
else
    echo "❌ Terraform initialization failed"
    exit 1
fi

echo ""
echo "3. Validating Terraform configuration..."
if terraform validate; then
    echo "✅ Terraform configuration is valid"
else
    echo "❌ Terraform validation failed"
    exit 1
fi

echo ""
echo "4. Running TFLint..."
if tflint; then
    echo "✅ TFLint checks passed"
else
    echo "❌ TFLint found issues"
    exit 1
fi

echo ""
echo "=== All validation checks passed! ==="
echo ""
echo "To deploy this infrastructure:"
echo "  1. Configure AWS credentials (AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)"
echo "  2. Run: terraform plan"
echo "  3. Run: terraform apply"
echo ""
echo "Configuration Summary:"
echo "  - API Name: stytch-appsync (configurable)"
echo "  - Auth Type: OIDC"
echo "  - OIDC Issuer: https://gaudy-barracuda-8765.customers.stytch.dev (configurable)"
echo "  - Environment: sandbox (configurable)"