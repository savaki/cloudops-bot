#!/bin/bash
set -e

# Clean up CloudOps Bot CloudFormation stack
# Usage: ./cleanup-stack.sh [environment]

ENV=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME="cloudops-${ENV}"

echo "======================================================================"
echo "CloudOps Stack Cleanup"
echo "======================================================================"
echo ""
echo "Environment: ${ENV}"
echo "Stack Name: ${STACK_NAME}"
echo "Region: ${AWS_REGION}"
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION} &>/dev/null; then
  echo "✅ Stack ${STACK_NAME} does not exist. Nothing to clean up."
  exit 0
fi

# Show current stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].StackStatus' \
  --output text)

echo "Current stack status: ${STACK_STATUS}"
echo ""

# Production safety check
if [ "$ENV" == "prod" ]; then
  echo "⚠️  WARNING: You are about to delete a PRODUCTION stack!"
  echo ""
  read -p "Type 'DELETE PRODUCTION' to confirm: " CONFIRM
  if [ "$CONFIRM" != "DELETE PRODUCTION" ]; then
    echo "Cleanup cancelled"
    exit 1
  fi
fi

# Confirmation prompt
read -p "Delete stack ${STACK_NAME}? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled"
  exit 0
fi

echo ""
echo "Deleting stack..."
aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${AWS_REGION}

echo "Waiting for deletion to complete (this may take 5-10 minutes)..."
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region ${AWS_REGION}

echo ""
echo "✅ Stack ${STACK_NAME} deleted successfully"
echo ""
echo "Note: The following resources are NOT deleted (by design):"
echo "  - DynamoDB tables (if deletion protection enabled)"
echo "  - ECR images (managed by lifecycle policy)"
echo "  - SSM Parameter Store secrets"
echo "  - CloudWatch log groups (retention policy applies)"
echo ""
