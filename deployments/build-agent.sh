#!/bin/bash
set -e

# Build and push CloudOps Bot agent Docker image to ECR
# Usage: ./build-agent.sh [environment] [region]

ENV=${1:-dev}
AWS_REGION=${2:-us-east-1}
STACK_NAME="cloudops-${ENV}"

echo "Building CloudOps Bot agent for environment: ${ENV}"

# Get ECR repository URI
REPOSITORY_URI=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
  --output text)

if [ -z "$REPOSITORY_URI" ] || [ "$REPOSITORY_URI" == "None" ]; then
  echo "Error: Could not find ECR repository URI"
  echo "Make sure the ${STACK_NAME} stack is deployed"
  exit 1
fi

echo "ECR Repository: ${REPOSITORY_URI}"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${REPOSITORY_URI}

# Build Docker image
echo "Building Docker image..."
docker build -f deployments/Dockerfile.agent -t cloudops-agent:latest .

# Tag image
echo "Tagging image..."
docker tag cloudops-agent:latest ${REPOSITORY_URI}:latest
docker tag cloudops-agent:latest ${REPOSITORY_URI}:$(git rev-parse --short HEAD)

# Push image
echo "Pushing image to ECR..."
docker push ${REPOSITORY_URI}:latest
docker push ${REPOSITORY_URI}:$(git rev-parse --short HEAD)

echo "✅ Successfully built and pushed agent image"
echo "Image: ${REPOSITORY_URI}:latest"
echo "Image: ${REPOSITORY_URI}:$(git rev-parse --short HEAD)"
