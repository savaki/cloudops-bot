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
	@echo "  make deploy-vpc           Deploy VPC stack"
	@echo "  make deploy-dynamodb      Deploy DynamoDB stack"
	@echo "  make deploy-iam           Deploy IAM stack"
	@echo "  make deploy-ecr           Deploy ECR stack"
	@echo "  make deploy-ecs           Deploy ECS stack"
	@echo "  make deploy-stepfunc      Deploy Step Functions stack"
	@echo "  make deploy-lambda        Deploy Lambda stack"
	@echo "  make deploy-apigateway    Deploy API Gateway stack"
	@echo "  make deploy-all           Deploy all stacks"
	@echo ""
	@echo "Development:"
	@echo "  make test                 Run tests"
	@echo "  make lint                 Run linter"
	@echo "  make fmt                  Format code"
	@echo "  make deps                 Download dependencies"
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
ENVIRONMENT ?= dev

deploy-vpc:
	@echo "Deploying VPC stack..."
	@aws cloudformation create-stack \
		--stack-name cloudops-vpc-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/01-vpc.yaml \
		--parameters ParameterKey=Environment,ParameterValue=$(ENVIRONMENT)
	@aws cloudformation wait stack-create-complete --stack-name cloudops-vpc-$(ENVIRONMENT)
	@echo "VPC stack deployed"

deploy-dynamodb:
	@echo "Deploying DynamoDB stack..."
	@aws cloudformation create-stack \
		--stack-name cloudops-dynamodb-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/02-dynamodb.yaml \
		--parameters ParameterKey=Environment,ParameterValue=$(ENVIRONMENT)
	@aws cloudformation wait stack-create-complete --stack-name cloudops-dynamodb-$(ENVIRONMENT)
	@echo "DynamoDB stack deployed"

deploy-iam:
	@echo "Getting DynamoDB table ARNs..."
	@export CONV_ARN=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableArn`].OutputValue' --output text) && \
	export HIST_ARN=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationHistoryTableArn`].OutputValue' --output text) && \
	echo "Deploying IAM stack..." && \
	aws cloudformation create-stack \
		--stack-name cloudops-iam-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/03-iam.yaml \
		--parameters \
			ParameterKey=Environment,ParameterValue=$(ENVIRONMENT) \
			ParameterKey=ConversationsTableArn,ParameterValue=$$CONV_ARN \
			ParameterKey=ConversationHistoryTableArn,ParameterValue=$$HIST_ARN \
		--capabilities CAPABILITY_NAMED_IAM && \
	aws cloudformation wait stack-create-complete --stack-name cloudops-iam-$(ENVIRONMENT) && \
	echo "IAM stack deployed"

deploy-ecr:
	@echo "Deploying ECR stack..."
	@aws cloudformation create-stack \
		--stack-name cloudops-ecr-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/04-ecr.yaml \
		--parameters ParameterKey=Environment,ParameterValue=$(ENVIRONMENT)
	@aws cloudformation wait stack-create-complete --stack-name cloudops-ecr-$(ENVIRONMENT)
	@echo "ECR stack deployed"

deploy-ecs:
	@echo "Getting stack outputs..."
	@export AGENT_REPO=$$(aws cloudformation describe-stacks --stack-name cloudops-ecr-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`AgentRepositoryUri`].OutputValue' --output text) && \
	export AGENT_ROLE=$$(aws cloudformation describe-stacks --stack-name cloudops-iam-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`CloudOpsAgentTaskRoleArn`].OutputValue' --output text) && \
	export EXEC_ROLE=$$(aws cloudformation describe-stacks --stack-name cloudops-iam-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ECSTaskExecutionRoleArn`].OutputValue' --output text) && \
	export CONV_TABLE=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableName`].OutputValue' --output text) && \
	export HIST_TABLE=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationHistoryTableName`].OutputValue' --output text) && \
	echo "Deploying ECS stack..." && \
	aws cloudformation create-stack \
		--stack-name cloudops-ecs-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/05-ecs.yaml \
		--parameters \
			ParameterKey=Environment,ParameterValue=$(ENVIRONMENT) \
			ParameterKey=AgentRepositoryUri,ParameterValue=$$AGENT_REPO \
			ParameterKey=AgentTaskRoleArn,ParameterValue=$$AGENT_ROLE \
			ParameterKey=ECSTaskExecutionRoleArn,ParameterValue=$$EXEC_ROLE \
			ParameterKey=ConversationsTableName,ParameterValue=$$CONV_TABLE \
			ParameterKey=ConversationHistoryTableName,ParameterValue=$$HIST_TABLE && \
	aws cloudformation wait stack-create-complete --stack-name cloudops-ecs-$(ENVIRONMENT) && \
	echo "ECS stack deployed"

deploy-stepfunc:
	@echo "Getting stack outputs..."
	@export ECS_CLUSTER=$$(aws cloudformation describe-stacks --stack-name cloudops-ecs-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ClusterArn`].OutputValue' --output text) && \
	export TASK_DEF=$$(aws cloudformation describe-stacks --stack-name cloudops-ecs-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text) && \
	export SF_ROLE=$$(aws cloudformation describe-stacks --stack-name cloudops-iam-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`StepFunctionsExecutionRoleArn`].OutputValue' --output text) && \
	export AGENT_SG=$$(aws cloudformation describe-stacks --stack-name cloudops-vpc-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`AgentSecurityGroupId`].OutputValue' --output text) && \
	export SUBNET1=$$(aws cloudformation describe-stacks --stack-name cloudops-vpc-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1Id`].OutputValue' --output text) && \
	export SUBNET2=$$(aws cloudformation describe-stacks --stack-name cloudops-vpc-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet2Id`].OutputValue' --output text) && \
	export CONV_TABLE=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableName`].OutputValue' --output text) && \
	echo "Deploying Step Functions stack..." && \
	aws cloudformation create-stack \
		--stack-name cloudops-stepfunctions-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/06-stepfunctions.yaml \
		--parameters \
			ParameterKey=Environment,ParameterValue=$(ENVIRONMENT) \
			ParameterKey=ECSClusterArn,ParameterValue=$$ECS_CLUSTER \
			ParameterKey=ECSTaskDefinitionArn,ParameterValue=$$TASK_DEF \
			ParameterKey=StepFunctionsRoleArn,ParameterValue=$$SF_ROLE \
			ParameterKey=ConversationsTableName,ParameterValue=$$CONV_TABLE \
			ParameterKey=AgentSecurityGroupId,ParameterValue=$$AGENT_SG \
			ParameterKey=PublicSubnet1,ParameterValue=$$SUBNET1 \
			ParameterKey=PublicSubnet2,ParameterValue=$$SUBNET2 && \
	aws cloudformation wait stack-create-complete --stack-name cloudops-stepfunctions-$(ENVIRONMENT) && \
	echo "Step Functions stack deployed"

deploy-lambda:
	@echo "Getting stack outputs..."
	@export LAMBDA_ROLE=$$(aws cloudformation describe-stacks --stack-name cloudops-iam-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`LambdaExecutionRoleArn`].OutputValue' --output text) && \
	export SF_ARN=$$(aws cloudformation describe-stacks --stack-name cloudops-stepfunctions-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text) && \
	export CONV_TABLE=$$(aws cloudformation describe-stacks --stack-name cloudops-dynamodb-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableName`].OutputValue' --output text) && \
	echo "Deploying Lambda stack..." && \
	aws cloudformation create-stack \
		--stack-name cloudops-lambda-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/07-lambda.yaml \
		--parameters \
			ParameterKey=Environment,ParameterValue=$(ENVIRONMENT) \
			ParameterKey=LambdaExecutionRoleArn,ParameterValue=$$LAMBDA_ROLE \
			ParameterKey=StepFunctionsArn,ParameterValue=$$SF_ARN \
			ParameterKey=ConversationsTableName,ParameterValue=$$CONV_TABLE && \
	aws cloudformation wait stack-create-complete --stack-name cloudops-lambda-$(ENVIRONMENT) && \
	echo "Lambda stack deployed"

deploy-apigateway:
	@echo "Getting Lambda outputs..."
	@export LAMBDA_ARN=$$(aws cloudformation describe-stacks --stack-name cloudops-lambda-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`SlackHandlerFunctionArn`].OutputValue' --output text) && \
	export LAMBDA_NAME=$$(aws cloudformation describe-stacks --stack-name cloudops-lambda-$(ENVIRONMENT) --query 'Stacks[0].Outputs[?OutputKey==`SlackHandlerFunctionName`].OutputValue' --output text) && \
	echo "Deploying API Gateway stack..." && \
	aws cloudformation create-stack \
		--stack-name cloudops-apigateway-$(ENVIRONMENT) \
		--template-body file://infrastructure/cloudformation/08-apigateway.yaml \
		--parameters \
			ParameterKey=Environment,ParameterValue=$(ENVIRONMENT) \
			ParameterKey=SlackHandlerFunctionArn,ParameterValue=$$LAMBDA_ARN \
			ParameterKey=SlackHandlerFunctionName,ParameterValue=$$LAMBDA_NAME && \
	aws cloudformation wait stack-create-complete --stack-name cloudops-apigateway-$(ENVIRONMENT) && \
	echo "API Gateway stack deployed"

deploy-all: deploy-vpc deploy-dynamodb deploy-iam deploy-ecr deploy-ecs deploy-stepfunc deploy-lambda
	@echo "All infrastructure stacks deployed"

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

# Monitoring
logs-lambda:
	@aws logs tail /aws/lambda/cloudops-slack-handler-$(ENVIRONMENT) --follow

logs-agent:
	@aws logs tail /ecs/cloudops-agent-$(ENVIRONMENT) --follow

logs-errors:
	@aws logs filter-log-events \
		--log-group-name /ecs/cloudops-agent-$(ENVIRONMENT) \
		--filter-pattern "ERROR"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf bin/
	@go clean

clean-all: clean
	@echo "WARNING: This will delete all CloudFormation stacks and DynamoDB data"
	@read -p "Continue? [y/N] " -n 1 -r && echo && \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		for stack in cloudops-apigateway-$(ENVIRONMENT) cloudops-lambda-$(ENVIRONMENT) cloudops-stepfunctions-$(ENVIRONMENT) \
		             cloudops-ecs-$(ENVIRONMENT) cloudops-ecr-$(ENVIRONMENT) cloudops-iam-$(ENVIRONMENT) \
		             cloudops-dynamodb-$(ENVIRONMENT) cloudops-vpc-$(ENVIRONMENT); do \
			echo "Deleting $$stack..."; \
			aws cloudformation delete-stack --stack-name $$stack; \
			aws cloudformation wait stack-delete-complete --stack-name $$stack || true; \
		done; \
		echo "Cleaning up Secrets Manager..."; \
		for secret in slack-bot-token slack-app-token slack-signing-key; do \
			aws secretsmanager delete-secret --secret-id $$secret --force-delete-without-recovery || true; \
		done; \
		echo "Cleanup complete"; \
	fi
