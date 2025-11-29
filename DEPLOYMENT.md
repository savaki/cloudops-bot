# CloudOps Bot Deployment Guide

Complete step-by-step guide to deploy the CloudOps bot to AWS.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Go 1.21+
- Docker
- Slack workspace with admin access
- AWS Account with permissions to create: VPC, DynamoDB, IAM, ECS, Lambda, Step Functions, ECR

## Phase 1: Slack App Setup

### 1.1 Create Slack App

1. Visit https://api.slack.com/apps
2. Click **"Create New App"** → **"From scratch"**
3. **App name**: CloudOps
4. **Workspace**: Select your workspace
5. Click **"Create App"**

### 1.2 Configure OAuth Scopes

1. Go to **"OAuth & Permissions"**
2. Under **"Scopes"** → **"Bot Token Scopes"**, add:
   - `app_mentions:read` - Detect @mentions
   - `channels:manage` - Create private channels
   - `channels:read` - List channels
   - `chat:write` - Post messages
   - `groups:write` - Create private channels
   - `groups:read` - Read private channels
   - `im:history` - Read message history
   - `users:read` - Get user information

### 1.3 Enable Socket Mode (Recommended)

1. Go to **"Socket Mode"**
2. Toggle **"Enable Socket Mode"** to ON
3. Click **"Generate App-Level Token"**
4. Name it: `xapp-cloudops`
5. **Copy the token** (starts with `xapp-`)

### 1.4 Install App & Get Bot Token

1. Go to **"Install App"**
2. Click **"Install to Workspace"**
3. Click **"Allow"** to authorize
4. Copy the **Bot Token** (starts with `xoxb-`)

### 1.5 Get Signing Key (if using API Gateway)

1. Go to **"Basic Information"**
2. Under **"App Credentials"**, find **"Signing Secret"**
3. Copy it (you'll use this later)

## Phase 2: AWS Infrastructure Setup

### 2.1 Store Slack Tokens in Secrets Manager

```bash
# Replace with your actual tokens
BOT_TOKEN="xoxb-..."
APP_TOKEN="xapp-..."
SIGNING_KEY="..."

aws secretsmanager create-secret \
  --name slack-bot-token \
  --secret-string "$BOT_TOKEN"

aws secretsmanager create-secret \
  --name slack-app-token \
  --secret-string "$APP_TOKEN"

aws secretsmanager create-secret \
  --name slack-signing-key \
  --secret-string "$SIGNING_KEY"
```

### 2.2 Deploy VPC Stack

```bash
aws cloudformation create-stack \
  --stack-name cloudops-vpc-dev \
  --template-body file://infrastructure/cloudformation/01-vpc.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev

# Wait for completion
aws cloudformation wait stack-create-complete --stack-name cloudops-vpc-dev
```

### 2.3 Deploy DynamoDB Stack

```bash
aws cloudformation create-stack \
  --stack-name cloudops-dynamodb-dev \
  --template-body file://infrastructure/cloudformation/02-dynamodb.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev

aws cloudformation wait stack-create-complete --stack-name cloudops-dynamodb-dev
```

### 2.4 Get Output Values from DynamoDB Stack

```bash
# You'll need these for the IAM stack
CONV_TABLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-dynamodb-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableArn`].OutputValue' \
  --output text)

HIST_TABLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-dynamodb-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ConversationHistoryTableArn`].OutputValue' \
  --output text)

echo "Conversations Table ARN: $CONV_TABLE_ARN"
echo "History Table ARN: $HIST_TABLE_ARN"
```

### 2.5 Deploy IAM Stack

```bash
aws cloudformation create-stack \
  --stack-name cloudops-iam-dev \
  --template-body file://infrastructure/cloudformation/03-iam.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=ConversationsTableArn,ParameterValue=$CONV_TABLE_ARN \
    ParameterKey=ConversationHistoryTableArn,ParameterValue=$HIST_TABLE_ARN \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete --stack-name cloudops-iam-dev
```

### 2.6 Deploy ECR Stack

```bash
aws cloudformation create-stack \
  --stack-name cloudops-ecr-dev \
  --template-body file://infrastructure/cloudformation/04-ecr.yaml \
  --parameters ParameterKey=Environment,ParameterValue=dev

aws cloudformation wait stack-create-complete --stack-name cloudops-ecr-dev
```

### 2.7 Deploy ECS Stack

```bash
# Get values from previous stacks
AGENT_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name cloudops-ecr-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`AgentRepositoryUri`].OutputValue' \
  --output text)

AGENT_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-iam-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudOpsAgentTaskRoleArn`].OutputValue' \
  --output text)

EXEC_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-iam-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ECSTaskExecutionRoleArn`].OutputValue' \
  --output text)

CONV_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cloudops-dynamodb-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ConversationsTableName`].OutputValue' \
  --output text)

HIST_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cloudops-dynamodb-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ConversationHistoryTableName`].OutputValue' \
  --output text)

# Deploy ECS
aws cloudformation create-stack \
  --stack-name cloudops-ecs-dev \
  --template-body file://infrastructure/cloudformation/05-ecs.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=AgentRepositoryUri,ParameterValue=$AGENT_REPO_URI \
    ParameterKey=AgentTaskRoleArn,ParameterValue=$AGENT_ROLE_ARN \
    ParameterKey=ECSTaskExecutionRoleArn,ParameterValue=$EXEC_ROLE_ARN \
    ParameterKey=ConversationsTableName,ParameterValue=$CONV_TABLE \
    ParameterKey=ConversationHistoryTableName,ParameterValue=$HIST_TABLE

aws cloudformation wait stack-create-complete --stack-name cloudops-ecs-dev
```

### 2.8 Deploy Step Functions Stack

```bash
# Get values
ECS_CLUSTER_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-ecs-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterArn`].OutputValue' \
  --output text)

TASK_DEF_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-ecs-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' \
  --output text)

STEPFUNC_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-iam-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`StepFunctionsExecutionRoleArn`].OutputValue' \
  --output text)

AGENT_SG_ID=$(aws cloudformation describe-stacks \
  --stack-name cloudops-vpc-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`AgentSecurityGroupId`].OutputValue' \
  --output text)

SUBNET1=$(aws cloudformation describe-stacks \
  --stack-name cloudops-vpc-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1Id`].OutputValue' \
  --output text)

SUBNET2=$(aws cloudformation describe-stacks \
  --stack-name cloudops-vpc-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet2Id`].OutputValue' \
  --output text)

# Deploy Step Functions
aws cloudformation create-stack \
  --stack-name cloudops-stepfunctions-dev \
  --template-body file://infrastructure/cloudformation/06-stepfunctions.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=ECSClusterArn,ParameterValue=$ECS_CLUSTER_ARN \
    ParameterKey=ECSTaskDefinitionArn,ParameterValue=$TASK_DEF_ARN \
    ParameterKey=StepFunctionsRoleArn,ParameterValue=$STEPFUNC_ROLE_ARN \
    ParameterKey=ConversationsTableName,ParameterValue=$CONV_TABLE \
    ParameterKey=AgentSecurityGroupId,ParameterValue=$AGENT_SG_ID \
    ParameterKey=PublicSubnet1,ParameterValue=$SUBNET1 \
    ParameterKey=PublicSubnet2,ParameterValue=$SUBNET2

aws cloudformation wait stack-create-complete --stack-name cloudops-stepfunctions-dev
```

### 2.9 Deploy Lambda Stack

```bash
# Get values
LAMBDA_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-iam-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaExecutionRoleArn`].OutputValue' \
  --output text)

STEPFUNC_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-stepfunctions-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
  --output text)

# Deploy Lambda
aws cloudformation create-stack \
  --stack-name cloudops-lambda-dev \
  --template-body file://infrastructure/cloudformation/07-lambda.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=LambdaExecutionRoleArn,ParameterValue=$LAMBDA_ROLE_ARN \
    ParameterKey=StepFunctionsArn,ParameterValue=$STEPFUNC_ARN \
    ParameterKey=ConversationsTableName,ParameterValue=$CONV_TABLE

aws cloudformation wait stack-create-complete --stack-name cloudops-lambda-dev
```

### 2.10 (Optional) Deploy API Gateway Stack

Only if you're using Events API instead of Socket Mode:

```bash
# Get values
LAMBDA_ARN=$(aws cloudformation describe-stacks \
  --stack-name cloudops-lambda-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackHandlerFunctionArn`].OutputValue' \
  --output text)

LAMBDA_NAME=$(aws cloudformation describe-stacks \
  --stack-name cloudops-lambda-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackHandlerFunctionName`].OutputValue' \
  --output text)

aws cloudformation create-stack \
  --stack-name cloudops-apigateway-dev \
  --template-body file://infrastructure/cloudformation/08-apigateway.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=dev \
    ParameterKey=SlackHandlerFunctionArn,ParameterValue=$LAMBDA_ARN \
    ParameterKey=SlackHandlerFunctionName,ParameterValue=$LAMBDA_NAME

aws cloudformation wait stack-create-complete --stack-name cloudops-apigateway-dev

# Get webhook URL
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name cloudops-apigateway-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text)

echo "Slack webhook URL: $WEBHOOK_URL"
```

## Phase 3: Build & Deploy Container

### 3.1 Implement Agent Container

Edit `cmd/agent/main.go` with your Claude API integration.

### 3.2 Build and Push Container

```bash
# Make script executable
chmod +x deployments/build-agent.sh

# Build and push to ECR
./deployments/build-agent.sh dev latest
```

### 3.3 Update ECS Task Definition

The ECS stack created the task definition with a placeholder image. You need to update it to use your new image:

```bash
# Get the cluster and task definition
CLUSTER=$(aws cloudformation describe-stacks \
  --stack-name cloudops-ecs-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
  --output text)

TASK_FAMILY=$(aws cloudformation describe-stacks \
  --stack-name cloudops-ecs-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionFamily`].OutputValue' \
  --output text)

# Get current task definition
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --query 'taskDefinition')

# Update the image in the container definition
UPDATED_TASK_DEF=$(echo $TASK_DEF | jq '.containerDefinitions[0].image = "'$AGENT_REPO_URI':latest"')

# Register new task definition (remove some CloudFormation fields first)
echo "$UPDATED_TASK_DEF" | jq '{
  family: .family,
  networkMode: .networkMode,
  requiresCompatibilities: .requiresCompatibilities,
  cpu: .cpu,
  memory: .memory,
  taskRoleArn: .taskRoleArn,
  executionRoleArn: .executionRoleArn,
  containerDefinitions: .containerDefinitions
}' > /tmp/task-def.json

aws ecs register-task-definition --cli-input-json file:///tmp/task-def.json
```

## Phase 4: Deploy Lambda Handler

### 4.1 Implement Lambda Handler

Edit `cmd/slack-handler/main.go` with Slack event handling logic.

### 4.2 Package and Deploy

```bash
# Make script executable
chmod +x deployments/package-lambda.sh

# Build and package
./deployments/package-lambda.sh dev slack-handler
```

## Phase 5: Configure Slack Webhook (if using API Gateway)

1. In Slack app settings, go to **"Event Subscriptions"**
2. Toggle **"Enable Events"** to ON
3. Under **"Request URL"**, paste your webhook URL:
   ```
   https://<api-id>.execute-api.<region>.amazonaws.com/dev/slack/events
   ```
4. Wait for verification (Slack will send a challenge request)
5. Under **"Subscribe to bot events"**, add:
   - `app_mention`
   - `message.groups` (for private channels)

## Phase 6: Test

### 6.1 Test in Slack

1. Go to your Slack workspace
2. Create a test channel `#cloudops`
3. Type: `@CloudOps hello`
4. Check:
   - CloudWatch logs: `/aws/lambda/cloudops-slack-handler-dev`
   - DynamoDB: `cloudops-conversations-dev` table
   - Step Functions: Check execution history
   - ECS: Check agent task logs at `/ecs/cloudops-agent-dev`

### 6.2 Check Logs

```bash
# Lambda logs
aws logs tail /aws/lambda/cloudops-slack-handler-dev --follow

# Agent logs
aws logs tail /ecs/cloudops-agent-dev --follow

# Recent errors
aws logs filter-log-events \
  --log-group-name /ecs/cloudops-agent-dev \
  --filter-pattern "ERROR"
```

## Troubleshooting

### Bot not responding

1. Check Lambda logs for errors
2. Verify Slack tokens are stored in Secrets Manager
3. Check that bot is installed in workspace
4. Verify Slack app scopes are correct

### Container fails to start

1. Check ECS agent logs
2. Verify DynamoDB table exists and is accessible
3. Check that environment variables are set in task definition
4. Verify IAM role has required permissions

### CloudFormation stack failed

1. Check stack events: `aws cloudformation describe-stack-events --stack-name <stack-name>`
2. Look for the specific error in the events
3. Fix the issue and delete/recreate the stack

## Cleanup

To remove all resources:

```bash
# Delete stacks in reverse order
for stack in cloudops-apigateway-dev cloudops-lambda-dev cloudops-stepfunctions-dev \
             cloudops-ecs-dev cloudops-ecr-dev cloudops-iam-dev cloudops-dynamodb-dev cloudops-vpc-dev; do
  aws cloudformation delete-stack --stack-name $stack
  aws cloudformation wait stack-delete-complete --stack-name $stack
done

# Delete Secrets Manager secrets
aws secretsmanager delete-secret --secret-id slack-bot-token --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id slack-app-token --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id slack-signing-key --force-delete-without-recovery
```

## Next Steps

1. Implement the agent container with Claude API integration
2. Implement Lambda handler for Slack events
3. Test end-to-end flow
4. Add monitoring and alerting
5. Set up CI/CD for automated deployments
