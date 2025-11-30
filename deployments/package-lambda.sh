#!/bin/bash
# Package and deploy CloudOps Lambda functions

set -e

# Configuration
ENV=${1:-dev}
HANDLER_NAME=${2:-slack-handler}
STACK_NAME="cloudops-${ENV}"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "======================================================================"
echo "CloudOps Lambda Build & Package"
echo "======================================================================"
echo "Environment: ${ENV}"
echo "Handler: ${HANDLER_NAME}"
echo "Region: ${AWS_REGION}"
echo ""

# Check Go is installed
if ! command -v go &> /dev/null; then
  echo "❌ Go compiler not found"
  echo ""
  echo "Install Go 1.21+ to continue:"
  echo "  - macOS: brew install go"
  echo "  - Linux: https://go.dev/doc/install"
  echo ""
  exit 1
fi

GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "✅ Go ${GO_VERSION} installed"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION} &>/dev/null; then
  echo "❌ Stack ${STACK_NAME} does not exist in ${AWS_REGION}"
  echo ""
  echo "Deploy the infrastructure first:"
  echo "  ./deployments/deploy-stack.sh ${ENV}"
  echo ""
  exit 1
fi
echo "✅ Stack ${STACK_NAME} exists"

# Build variables
BUILD_DIR="./bin"
LAMBDA_BINARY="${BUILD_DIR}/${HANDLER_NAME}"
LAMBDA_ZIP="${BUILD_DIR}/lambda-${HANDLER_NAME}.zip"

# Create build directory
mkdir -p "$BUILD_DIR"

# Build the Lambda handler binary
echo ""
echo "Building Lambda handler for ${HANDLER_NAME}..."
GOOS=linux GOARCH=arm64 go build \
  -o "$LAMBDA_BINARY" \
  "./cmd/${HANDLER_NAME}"

if [ ! -f "$LAMBDA_BINARY" ]; then
  echo "❌ Failed to build Lambda binary"
  echo ""
  echo "Verify the source code exists:"
  echo "  ./cmd/${HANDLER_NAME}/main.go"
  echo ""
  exit 1
fi

BINARY_SIZE=$(ls -lh "$LAMBDA_BINARY" | awk '{print $5}')
echo "✅ Binary built: ${BINARY_SIZE}"

# Create deployment package
echo ""
echo "Creating deployment package..."
cd "$BUILD_DIR"

# Remove old zip if it exists
rm -f "lambda-${HANDLER_NAME}.zip"

# Rename binary to 'bootstrap' (required for provided.al2 runtime)
cp "${HANDLER_NAME}" bootstrap

# Create zip file with the bootstrap binary
zip -q "lambda-${HANDLER_NAME}.zip" bootstrap

if [ ! -f "lambda-${HANDLER_NAME}.zip" ]; then
  echo "❌ Failed to create zip file"
  exit 1
fi

# Cleanup
rm -f bootstrap

PACKAGE_SIZE=$(ls -lh "lambda-${HANDLER_NAME}.zip" | awk '{print $5}')
echo "✅ Package created: ${PACKAGE_SIZE}"

cd - > /dev/null

# Get Lambda function name from CloudFormation
echo ""
echo "Getting Lambda function name from CloudFormation..."
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query "Stacks[0].Outputs[?OutputKey=='SlackHandlerFunctionName'].OutputValue" \
  --output text)

if [ -z "$LAMBDA_FUNCTION" ] || [ "$LAMBDA_FUNCTION" == "None" ]; then
  echo "❌ Could not find Lambda function in CloudFormation outputs"
  echo ""
  echo "Verify the stack deployed correctly:"
  echo "  aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo ""
  exit 1
fi

echo "Lambda function: ${LAMBDA_FUNCTION}"

# Deploy to Lambda
echo ""
echo "Deploying to Lambda..."
aws lambda update-function-code \
  --function-name "$LAMBDA_FUNCTION" \
  --zip-file "fileb://${BUILD_DIR}/lambda-${HANDLER_NAME}.zip" \
  --region ${AWS_REGION} \
  --no-cli-pager > /dev/null

echo ""
echo "======================================================================"
echo "✅ Lambda Function Deployed Successfully"
echo "======================================================================"
echo "Function: ${LAMBDA_FUNCTION}"
echo "Package: ${BUILD_DIR}/lambda-${HANDLER_NAME}.zip"
echo "Size: ${PACKAGE_SIZE}"
echo ""
