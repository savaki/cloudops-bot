#!/bin/bash
set -e

# Quick rebuild and test for Docker container development
# Usage: ./scripts/rebuild-and-test-docker.sh [conversation-id]
#
# This script is optimized for rapid iteration:
# - Builds Docker image
# - Reuses existing conversation or creates new one
# - Runs container

IMAGE_NAME="cloudops-agent:test"

echo "🔨 Rebuilding Docker image..."
docker build -f deployments/Dockerfile.agent -t ${IMAGE_NAME} -q .

echo "✅ Build complete"
echo ""

# Run the test
./scripts/test-agent-docker.sh "$@"
