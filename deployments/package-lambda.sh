#!/bin/bash
# Package and deploy CloudOps Lambda functions

set -e

# Configuration
ENV=${1:-dev}
HANDLER_NAME=${2:-slack-handler}
STACK_NAME="cloudops-${ENV}"

echo "=== CloudOps Lambda Build & Package ==="
echo "Environment: $ENV"
echo "Handler: $HANDLER_NAME"
echo ""

# Build variables
BUILD_DIR="./bin"
LAMBDA_BINARY="${BUILD_DIR}/${HANDLER_NAME}"
LAMBDA_ZIP="${BUILD_DIR}/lambda-${HANDLER_NAME}.zip"

# Create build directory
mkdir -p "$BUILD_DIR"

# Build the Lambda handler binary
echo "Building Lambda handler for $HANDLER_NAME..."
GOOS=linux GOARCH=arm64 go build \
  -o "$LAMBDA_BINARY" \
  "./cmd/${HANDLER_NAME}"

if [ ! -f "$LAMBDA_BINARY" ]; then
  echo "Error: Failed to build Lambda binary"
  exit 1
fi

echo "Binary built: $LAMBDA_BINARY"
echo ""

# Create deployment package
echo "Creating deployment package..."
cd "$BUILD_DIR"

# Remove old zip if it exists
rm -f "lambda-${HANDLER_NAME}.zip"

# Rename binary to 'bootstrap' (required for provided.al2 runtime)
cp "${HANDLER_NAME}" bootstrap

# Create zip file with the bootstrap binary
zip -j "lambda-${HANDLER_NAME}.zip" bootstrap

if [ ! -f "lambda-${HANDLER_NAME}.zip" ]; then
  echo "Error: Failed to create zip file"
  exit 1
fi

# Cleanup
rm -f bootstrap

echo "Package created: lambda-${HANDLER_NAME}.zip"
echo "Size: $(ls -lh lambda-${HANDLER_NAME}.zip | awk '{print $5}')"
echo ""

cd - > /dev/null

# Get Lambda function name from CloudFormation
echo "Getting Lambda function name from CloudFormation..."
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='SlackHandlerFunctionName'].OutputValue" \
  --output text)

if [ -z "$LAMBDA_FUNCTION" ] || [ "$LAMBDA_FUNCTION" == "None" ]; then
  echo "Error: Could not find Lambda function in CloudFormation"
  echo "Make sure the stack '${STACK_NAME}' exists and has been deployed"
  echo ""
  echo "Deploy the stack with:"
  echo "  ./deployments/deploy-stack.sh ${ENV}"
  exit 1
fi

echo "Lambda function: $LAMBDA_FUNCTION"
echo ""

# Deploy to Lambda
echo "Deploying to Lambda..."
aws lambda update-function-code \
  --function-name "$LAMBDA_FUNCTION" \
  --zip-file "fileb://${BUILD_DIR}/lambda-${HANDLER_NAME}.zip"

echo ""
echo "=== Deployment Complete ==="
echo "Function: $LAMBDA_FUNCTION"
echo "Package: ${BUILD_DIR}/lambda-${HANDLER_NAME}.zip"
echo ""
echo "Next step: Configure Slack webhook URL"
echo ""
echo "Get the webhook URL with:"
echo "  aws cloudformation describe-stacks \\"
echo "    --stack-name ${STACK_NAME} \\"
echo "    --query 'Stacks[0].Outputs[?OutputKey==\`SlackWebhookUrl\`].OutputValue' \\"
echo "    --output text"
echo ""
