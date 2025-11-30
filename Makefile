.PHONY: help build test clean deploy logs

help:
	@echo "CloudOps Bot - Available Commands"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build-agent          Build agent container"
	@echo "  make push-agent           Push agent to ECR"
	@echo "  make build-agent-local    Build agent binary for testing"
	@echo "  make build-lambda         Build Lambda handler binary"
	@echo "  make package-lambda       Package Lambda for deployment"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make deploy-stack         Deploy infrastructure (VPC, DynamoDB, IAM, ECR, ECS, etc.)"
	@echo "  make deploy-full          Deploy infrastructure + build Lambda + build Docker image"
	@echo "  make cleanup              Clean up all AWS resources"
	@echo ""
	@echo "Development:"
	@echo "  make test                 Run tests"
	@echo "  make lint                 Run linter"
	@echo "  make fmt                  Format code"
	@echo "  make deps                 Download dependencies"
	@echo ""
	@echo "Local Testing:"
	@echo "  make local-start          Start local DynamoDB"
	@echo "  make local-setup          Setup local DynamoDB tables"
	@echo "  make local-test           Run interactive agent testing"
	@echo "  make local-docker         Build and test agent Docker container"
	@echo "  make local-rebuild        Quick rebuild and test Docker container"
	@echo "  make local-stop           Stop local services"
	@echo ""
	@echo "Slack Configuration:"
	@echo "  make slack-manifest       Generate Slack app manifest from deployed stack"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs-lambda          Show Lambda logs"
	@echo "  make logs-agent           Show ECS agent logs"
	@echo "  make logs-errors          Show error logs"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                Clean build artifacts"
	@echo "  make clean-all            Delete all stacks and artifacts"

# Build targets
build-agent:
	@echo "Building agent container..."
	@./deployments/build-agent.sh dev latest

push-agent: build-agent
	@echo "Agent already pushed to ECR"

build-agent-local:
	@echo "Building agent binary..."
	@GOOS=linux GOARCH=arm64 go build -o bin/agent ./cmd/agent

build-lambda:
	@echo "Building Lambda handler..."
	@GOOS=linux GOARCH=arm64 go build -o bin/slack-handler ./cmd/slack-handler

package-lambda: build-lambda
	@echo "Packaging Lambda..."
	@./deployments/package-lambda.sh dev slack-handler

# Infrastructure deployment
ENV ?= dev
AWS_REGION ?= us-east-1

deploy-stack:
	@echo "Deploying CloudOps infrastructure stack..."
	@./deployments/deploy-stack.sh $(ENV)

deploy-full:
	@echo "Deploying CloudOps infrastructure + building code..."
	@./deployments/deploy-stack.sh $(ENV) --full

cleanup:
	@echo "Cleaning up CloudOps resources..."
	@./deployments/cleanup-stack.sh $(ENV)

# Development targets
test:
	@echo "Running tests..."
	@go test -v ./...

lint:
	@echo "Running linter..."
	@golangci-lint run ./...

fmt:
	@echo "Formatting code..."
	@go fmt ./...

deps:
	@echo "Downloading dependencies..."
	@go mod download
	@go mod tidy

# Local Testing
local-start:
	@echo "Starting local DynamoDB..."
	@docker-compose up -d
	@echo "DynamoDB Local: http://localhost:8000"
	@echo "DynamoDB Admin: http://localhost:8001"

local-setup: local-start
	@echo "Setting up local DynamoDB tables..."
	@./scripts/setup-local-dynamodb.sh

local-test:
	@./scripts/test-agent-interactive.sh

local-docker:
	@./scripts/test-agent-docker.sh

local-rebuild:
	@./scripts/rebuild-and-test-docker.sh

local-stop:
	@echo "Stopping local services..."
	@docker-compose down

local-clean: local-stop
	@echo "Cleaning local data..."
	@docker-compose down -v

# Slack Configuration
slack-manifest:
	@./scripts/generate-slack-manifest.sh $(ENV)

# Monitoring
logs-lambda:
	@aws logs tail /aws/lambda/cloudops-slack-handler-$(ENV) --follow

logs-agent:
	@aws logs tail /ecs/cloudops-agent-$(ENV) --follow

logs-errors:
	@aws logs filter-log-events \
		--log-group-name /ecs/cloudops-agent-$(ENV) \
		--filter-pattern "ERROR"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf bin/
	@go clean

clean-all: clean cleanup
	@echo "All build artifacts and AWS resources have been cleaned up"
