#!/bin/bash
set -e

# Build and push CloudOps Bot agent Docker image to ECR
# Usage: ./build-agent.sh [environment] [region]

ENV=${1:-dev}
AWS_REGION=${2:-us-east-1}
STACK_NAME="cloudops-${ENV}"

echo "======================================================================"
echo "Building CloudOps Bot Agent"
echo "======================================================================"
echo "Environment: ${ENV}"
echo "Region: ${AWS_REGION}"
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running"
  echo ""
  echo "Please start Docker and retry:"
  echo "  - macOS: Start Docker Desktop"
  echo "  - Linux: sudo systemctl start docker"
  echo ""
  exit 1
fi
echo "✅ Docker is running"

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

# Get ECR repository URI
echo ""
echo "Getting ECR repository URI..."
REPOSITORY_URI=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
  --output text)

if [ -z "$REPOSITORY_URI" ] || [ "$REPOSITORY_URI" == "None" ]; then
  echo "❌ Could not find ECR repository URI in stack outputs"
  echo ""
  echo "Verify the stack deployed correctly:"
  echo "  aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo ""
  exit 1
fi

echo "ECR Repository: ${REPOSITORY_URI}"

# Login to ECR
echo ""
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${REPOSITORY_URI} > /dev/null 2>&1
echo "✅ Authenticated with ECR"

# Build Docker image
echo ""
echo "Building Docker image..."
docker build -f deployments/Dockerfile.agent -t cloudops-agent:latest .

# Get git commit hash for tagging
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "local")

# Show image size
echo ""
echo "Image built successfully!"
IMAGE_SIZE=$(docker images cloudops-agent:latest --format "{{.Size}}")
echo "Image size: ${IMAGE_SIZE}"

# Tag image
echo ""
echo "Tagging image..."
docker tag cloudops-agent:latest ${REPOSITORY_URI}:latest
docker tag cloudops-agent:latest ${REPOSITORY_URI}:${GIT_COMMIT}
echo "  - ${REPOSITORY_URI}:latest"
echo "  - ${REPOSITORY_URI}:${GIT_COMMIT}"

# Push image
echo ""
echo "Pushing image to ECR..."
DOCKER_OUTPUT=$(mktemp)

echo "Pushing ${REPOSITORY_URI}:latest..."
if ! docker push ${REPOSITORY_URI}:latest > "$DOCKER_OUTPUT" 2>&1; then
  echo "❌ Docker push failed (latest tag):"
  cat "$DOCKER_OUTPUT"
  rm -f "$DOCKER_OUTPUT"
  exit 1
fi

echo "Pushing ${REPOSITORY_URI}:${GIT_COMMIT}..."
if ! docker push ${REPOSITORY_URI}:${GIT_COMMIT} > "$DOCKER_OUTPUT" 2>&1; then
  echo "❌ Docker push failed (${GIT_COMMIT} tag):"
  cat "$DOCKER_OUTPUT"
  rm -f "$DOCKER_OUTPUT"
  exit 1
fi
rm -f "$DOCKER_OUTPUT"

echo ""
echo "======================================================================"
echo "✅ Agent Image Deployed Successfully"
echo "======================================================================"
echo "Repository: ${REPOSITORY_URI}"
echo "Tags: latest, ${GIT_COMMIT}"
echo "Size: ${IMAGE_SIZE}"
echo ""
