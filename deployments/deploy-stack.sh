#!/bin/bash
set -e

# Deploy CloudOps Bot complete infrastructure stack
# Usage: ./deploy-stack.sh [environment] [--full]
#   environment: dev, staging, prod (default: dev)
#   --full: Deploy infrastructure + build Lambda + build Docker image

# Parse command line arguments
FULL_DEPLOYMENT=false
ENV="dev"

while [[ $# -gt 0 ]]; do
  case $1 in
    --full)
      FULL_DEPLOYMENT=true
      shift
      ;;
    *)
      ENV=$1
      shift
      ;;
  esac
done

AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME="cloudops-${ENV}"

# Get the script directory to use absolute paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="${PROJECT_ROOT}/infrastructure/cloudformation/cloudops-stack.yaml"

# Error handler - show stack events on failure
cleanup_on_error() {
  echo ""
  echo "======================================================================"
  echo "❌ Deployment Failed"
  echo "======================================================================"

  # Show recent stack events for debugging
  if aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo ""
    echo "Recent stack events (most recent first):"
    aws cloudformation describe-stack-events \
      --stack-name ${STACK_NAME} \
      --region ${AWS_REGION} \
      --max-items 10 \
      --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,ResourceStatusReason]' \
      --output table 2>/dev/null || true
  fi

  echo ""
  echo "To clean up: ./deployments/cleanup-stack.sh ${ENV}"

  exit 1
}

trap cleanup_on_error ERR

echo "======================================================================"
echo "CloudOps Bot Deployment"
echo "======================================================================"
echo "Environment: ${ENV}"
echo "Region: ${AWS_REGION}"
echo "Stack Name: ${STACK_NAME}"
echo "Template: ${TEMPLATE_PATH}"
if [ "$FULL_DEPLOYMENT" == "true" ]; then
  echo "Mode: FULL (Infrastructure + Lambda + Docker)"
else
  echo "Mode: Infrastructure Only"
fi
echo ""

# Validate template exists
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "❌ CloudFormation template not found: ${TEMPLATE_PATH}"
  exit 1
fi

echo "======================================================================"
echo "Checking Prerequisites"
echo "======================================================================"

# Validate region supports Bedrock
echo "Validating region..."
BEDROCK_REGIONS=("us-east-1" "us-west-2" "eu-central-1" "ap-southeast-1" "ap-northeast-1")
REGION_SUPPORTED=false

for region in "${BEDROCK_REGIONS[@]}"; do
  [ "$region" == "$AWS_REGION" ] && REGION_SUPPORTED=true && break
done

if [ "$REGION_SUPPORTED" == false ]; then
  echo "   ⚠️  Warning: ${AWS_REGION} may not support AWS Bedrock Claude 3.5 Sonnet v2"
  echo "   Verified regions: ${BEDROCK_REGIONS[@]}"
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  echo "   ✅ Region ${AWS_REGION} supports Bedrock"
fi

echo ""

# Check if parameters exist
echo "Checking AWS Systems Manager Parameter Store..."
for param in /cloudops/${ENV}/slack-bot-token /cloudops/${ENV}/slack-signing-key; do
  if aws ssm get-parameter --name ${param} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "   ✅ ${param}"
  else
    echo "   ❌ ${param} - NOT FOUND"
    echo ""
    echo "Please create the parameters with:"
    echo "  ./deployments/setup-secrets.sh ${ENV} --interactive"
    echo ""
    echo "Or manually:"
    echo "  aws ssm put-parameter --name ${param} --value 'your-value' --type SecureString --region ${AWS_REGION}"
    exit 1
  fi
done

echo "Checking Bedrock Model Access..."
BEDROCK_MODEL="anthropic.claude-3-5-sonnet-20241022-v2:0"
if aws bedrock list-foundation-models --region ${AWS_REGION} --query "modelSummaries[?modelId=='${BEDROCK_MODEL}'].modelId" --output text 2>/dev/null | grep -q "${BEDROCK_MODEL}"; then
  echo "   ✅ ${BEDROCK_MODEL} is available"
else
  echo "   ❌ AWS Bedrock Claude 3.5 Sonnet v2 is NOT enabled in ${AWS_REGION}"
  echo ""
  echo "Enable model access:"
  echo "   1. Go to AWS Console → Bedrock → Model Access"
  echo "      https://console.aws.amazon.com/bedrock/home?region=${AWS_REGION}#/modelaccess"
  echo "   2. Click 'Modify model access'"
  echo "   3. Enable: anthropic.claude-3-5-sonnet-20241022-v2:0"
  echo "   4. Submit request (usually instant approval)"
  echo "   5. Wait 2-3 minutes for activation"
  echo ""
  echo "After enabling, re-run: ./deployments/deploy-stack.sh ${ENV}"
  exit 1
fi

echo ""
echo "======================================================================"
echo "Deploying CloudFormation Stack"
echo "======================================================================"

# Check if stack exists and its status
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
  echo "Stack does not exist. Creating..."
  OPERATION="create-stack"
elif [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]; then
  echo "❌ Stack is in ROLLBACK_COMPLETE state from a previous failed deployment"
  echo ""
  echo "Stack resources have been rolled back but the stack still exists."
  echo "You must delete the stack before deploying again."
  echo ""
  echo "To clean up and retry:"
  echo "   aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo "   aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo "   ./deployments/deploy-stack.sh ${ENV}"
  echo ""
  echo "Or use the cleanup script:"
  echo "   ./deployments/cleanup-stack.sh ${ENV}"
  exit 1
elif [[ "$STACK_STATUS" == *"IN_PROGRESS"* ]]; then
  echo "❌ Stack operation already in progress (${STACK_STATUS}). Please wait for it to complete."
  exit 1
else
  echo "Stack exists (${STACK_STATUS}). Updating..."
  OPERATION="update-stack"
fi

# Deploy stack
if [ "$OPERATION" == "create-stack" ]; then
  aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://${TEMPLATE_PATH} \
    --parameters \
      ParameterKey=Env,ParameterValue=${ENV} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION}

  echo ""
  echo "Waiting for stack creation to complete..."
  aws cloudformation wait stack-create-complete \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION}
else
  # Try to update, but handle "No updates" gracefully
  UPDATE_OUTPUT=$(aws cloudformation update-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://${TEMPLATE_PATH} \
    --parameters \
      ParameterKey=Env,ParameterValue=${ENV} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION} 2>&1) || UPDATE_EXIT_CODE=$?

  if [ ${UPDATE_EXIT_CODE:-0} -ne 0 ]; then
    if echo "$UPDATE_OUTPUT" | grep -q "No updates are to be performed"; then
      echo ""
      echo "✅ No updates needed - stack is already up to date"
    else
      echo "❌ Update failed:"
      echo "$UPDATE_OUTPUT"
      exit ${UPDATE_EXIT_CODE}
    fi
  else
    echo ""
    echo "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
      --stack-name ${STACK_NAME} \
      --region ${AWS_REGION}
  fi
fi

# Function to build and deploy Lambda
deploy_lambda() {
  echo ""
  echo "======================================================================"
  echo "Building and Deploying Lambda Function"
  echo "======================================================================"

  # Check Go is installed
  if ! command -v go &> /dev/null; then
    echo "❌ Go compiler not found. Install Go 1.21+ to continue."
    exit 1
  fi

  LAMBDA_DIR="${PROJECT_ROOT}/bin"
  mkdir -p ${LAMBDA_DIR}

  echo "Building Lambda handler for arm64..."
  cd ${PROJECT_ROOT}
  GOOS=linux GOARCH=arm64 go build -o ${LAMBDA_DIR}/slack-handler ./cmd/slack-handler

  if [ ! -f "${LAMBDA_DIR}/slack-handler" ]; then
    echo "❌ Failed to build Lambda handler"
    exit 1
  fi

  # Create deployment package
  cd ${LAMBDA_DIR}
  cp slack-handler bootstrap
  zip -q lambda-slack-handler.zip bootstrap
  rm bootstrap
  cd - > /dev/null

  # Get Lambda function name from stack outputs
  LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query "Stacks[0].Outputs[?OutputKey=='SlackHandlerFunctionName'].OutputValue" \
    --output text)

  echo "Deploying to Lambda function: ${LAMBDA_FUNCTION}..."
  aws lambda update-function-code \
    --function-name ${LAMBDA_FUNCTION} \
    --zip-file fileb://${LAMBDA_DIR}/lambda-slack-handler.zip \
    --region ${AWS_REGION} \
    --no-cli-pager > /dev/null

  echo "✅ Lambda function deployed"
}

# Function to build and push agent image
deploy_agent() {
  echo ""
  echo "======================================================================"
  echo "Building and Pushing Agent Container Image"
  echo "======================================================================"

  # Check Docker is running
  if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and retry."
    exit 1
  fi

  # Get ECR repository URI from stack outputs
  REPOSITORY_URI=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
    --output text)

  echo "ECR Repository: ${REPOSITORY_URI}"

  # Login to ECR
  echo "Authenticating with ECR..."
  aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${REPOSITORY_URI} > /dev/null 2>&1

  # Build image
  echo "Building agent container image..."
  cd ${PROJECT_ROOT}
  DOCKER_OUTPUT=$(mktemp)
  if ! docker build -f deployments/Dockerfile.agent -t cloudops-agent:latest . > "$DOCKER_OUTPUT" 2>&1; then
    echo "❌ Docker build failed:"
    cat "$DOCKER_OUTPUT"
    rm -f "$DOCKER_OUTPUT"
    exit 1
  fi
  rm -f "$DOCKER_OUTPUT"

  # Get git commit hash for tagging
  GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

  # Tag and push
  echo "Pushing to ECR (tags: latest, ${GIT_COMMIT})..."
  docker tag cloudops-agent:latest ${REPOSITORY_URI}:latest
  docker tag cloudops-agent:latest ${REPOSITORY_URI}:${GIT_COMMIT}

  DOCKER_OUTPUT=$(mktemp)
  if ! docker push ${REPOSITORY_URI}:latest > "$DOCKER_OUTPUT" 2>&1; then
    echo "❌ Docker push failed (latest tag):"
    cat "$DOCKER_OUTPUT"
    rm -f "$DOCKER_OUTPUT"
    exit 1
  fi
  if ! docker push ${REPOSITORY_URI}:${GIT_COMMIT} > "$DOCKER_OUTPUT" 2>&1; then
    echo "❌ Docker push failed (${GIT_COMMIT} tag):"
    cat "$DOCKER_OUTPUT"
    rm -f "$DOCKER_OUTPUT"
    exit 1
  fi
  rm -f "$DOCKER_OUTPUT"

  echo "✅ Agent image deployed"
}

# Execute full deployment if requested
if [ "$FULL_DEPLOYMENT" == "true" ]; then
  deploy_lambda
  deploy_agent
fi

echo ""
echo "======================================================================"
if [ "$FULL_DEPLOYMENT" == "true" ]; then
  echo "🎉 Full Deployment Complete!"
else
  echo "✅ CloudFormation Stack Deployed Successfully"
fi
echo "======================================================================"

# Get outputs
echo ""
echo "Stack Outputs:"
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table \
  --region ${AWS_REGION}

# Get webhook URL
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

echo ""
echo "======================================================================"
echo "Next Steps"
echo "======================================================================"
echo ""

if [ "$FULL_DEPLOYMENT" == "true" ]; then
  echo "1. Configure Slack app event subscription:"
  if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "None" ]; then
    echo "   ${WEBHOOK_URL}"
  else
    echo "   ⚠️  Could not retrieve webhook URL. Check stack outputs manually."
  fi
  echo ""
  echo "2. Test by mentioning your bot in a Slack channel"
  echo ""
else
  echo "1. Build and push agent Docker image:"
  echo "   ./deployments/build-agent.sh ${ENV} ${AWS_REGION}"
  echo ""
  echo "2. Package and deploy Lambda function:"
  echo "   ./deployments/package-lambda.sh ${ENV} slack-handler"
  echo ""
  echo "3. Configure Slack app event subscription:"
  if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "None" ]; then
    echo "   ${WEBHOOK_URL}"
  else
    echo "   ⚠️  Could not retrieve webhook URL. Check stack outputs manually."
  fi
  echo ""
  echo "Or re-run with --full flag for automated deployment:"
  echo "   ./deployments/deploy-stack.sh ${ENV} --full"
  echo ""
fi
