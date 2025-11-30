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

### 2.1 Store Slack Secrets in Parameter Store

CloudOps Bot uses AWS Systems Manager Parameter Store (free tier) instead of Secrets Manager to store Slack credentials.

**Using the Setup Script (Recommended)**:

```bash
# Interactive mode - prompts for each secret
./deployments/setup-secrets.sh dev --interactive

# Or provide values directly
./deployments/setup-secrets.sh dev \
  --slack-bot-token xoxb-your-token \
  --slack-signing-key your-signing-secret
```

**Manual Setup**:

```bash
ENV=dev

# Store Slack bot token
aws ssm put-parameter \
  --name "/cloudops/${ENV}/slack-bot-token" \
  --value "xoxb-your-token-here" \
  --type SecureString \
  --overwrite

# Store Slack signing secret
aws ssm put-parameter \
  --name "/cloudops/${ENV}/slack-signing-key" \
  --value "your-signing-secret-here" \
  --type SecureString \
  --overwrite
```

### 2.2 Enable AWS Bedrock Model Access

CloudOps Bot uses AWS Bedrock (not Claude API) for AI capabilities.

1. Go to AWS Console → Amazon Bedrock → Model Access
2. Click **Request model access**
3. Enable: **Anthropic Claude 3.5 Sonnet v2** (`anthropic.claude-3-5-sonnet-20241022-v2:0`)
4. Wait 2-3 minutes for activation

**Supported Regions**: us-east-1, us-west-2, eu-central-1, ap-southeast-1, ap-northeast-1

### 2.3 Deploy Infrastructure Stack

#### Quick Deployment (Recommended)

Deploy all infrastructure with a single command:

```bash
./deployments/deploy-stack.sh dev
```

This script will:
- Validate that secrets exist in Parameter Store
- Check AWS Bedrock model access
- Deploy the complete CloudFormation stack (VPC, DynamoDB, IAM, ECR, ECS, Lambda, API Gateway, Step Functions)
- Display the webhook URL for Slack configuration

#### Full Deployment (Infrastructure + Code)

For a complete end-to-end deployment including Lambda code and Docker image:

```bash
./deployments/deploy-stack.sh dev --full
```

This requires:
- Go 1.21+ installed
- Docker running
- Adds 3-5 minutes to deployment time
- Results in a fully functional deployment

#### Manual Deployment (Advanced)

If you prefer manual control:

```bash
aws cloudformation create-stack \
  --stack-name cloudops-dev \
  --template-body file://infrastructure/cloudformation/cloudops-stack.yaml \
  --parameters ParameterKey=Env,ParameterValue=dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion (takes 3-5 minutes)
aws cloudformation wait stack-create-complete --stack-name cloudops-dev --region us-east-1

# Get webhook URL
aws cloudformation describe-stacks \
  --stack-name cloudops-dev \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text
```

### 2.4 What Gets Deployed

The single CloudFormation stack (`cloudops-stack.yaml`) creates all required resources:

**Networking**:
- VPC (10.0.0.0/16) with 2 public subnets across availability zones
- Internet Gateway and route tables
- Security group for ECS agents

**Data Storage**:
- `cloudops-conversations-{env}` DynamoDB table (with GSIs for channel and status queries, TTL enabled)
- `cloudops-conversation-history-{env}` DynamoDB table (with TTL enabled)

**IAM Roles**:
- Lambda execution role (access to DynamoDB, Step Functions, Parameter Store, CloudWatch)
- ECS task execution role (pull images from ECR, write logs)
- ECS task role (access to DynamoDB, Bedrock, CloudWatch)
- Step Functions execution role (start ECS tasks)

**Container Infrastructure**:
- ECR repository for agent Docker images (with lifecycle policy to keep last 10 images)
- ECS Fargate cluster
- ECS task definition (1 vCPU, 2GB RAM, arm64)

**Orchestration**:
- Step Functions state machine for ECS task orchestration

**Event Handling**:
- Lambda function for Slack webhook handling (Go binary, arm64, placeholder code)
- API Gateway REST API with `/slack/events` endpoint

### 2.5 Deployment Outputs

After successful deployment, you'll see:

```
======================================================================
✅ CloudFormation Stack Deployed Successfully
======================================================================

Stack Outputs:
  ECR Repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cloudops-dev
  Lambda Function: cloudops-slack-handler-dev
  Webhook URL: https://abc123.execute-api.us-east-1.amazonaws.com/dev/slack/events

Next steps:
  1. Build and push agent Docker image:
     ./deployments/build-agent.sh dev us-east-1

  2. Package and deploy Lambda function:
     ./deployments/package-lambda.sh dev slack-handler

  3. Configure Slack app event subscription:
     https://abc123.execute-api.us-east-1.amazonaws.com/dev/slack/events

Or re-run with --full flag for automated deployment:
  ./deployments/deploy-stack.sh dev --full
```

## Phase 3: Build & Deploy Container

The agent container runs in ECS Fargate and handles the actual conversation processing using AWS Bedrock.

### 3.1 Build and Push Container

```bash
# Build and push to ECR (automatically tags with 'latest' and git commit hash)
./deployments/build-agent.sh dev us-east-1
```

This script will:
- Authenticate with ECR
- Build the Docker image from `deployments/Dockerfile.agent`
- Tag with `latest` and current git commit hash
- Push both tags to ECR

**Note**: If you used `--full` flag in Phase 2, this step is already complete.

## Phase 4: Deploy Lambda Handler

The Lambda function handles incoming Slack events and triggers Step Functions executions.

### 4.1 Package and Deploy

```bash
# Build, package, and deploy Lambda function
./deployments/package-lambda.sh dev slack-handler
```

This script will:
- Build the Go binary for Linux arm64
- Create a deployment ZIP package with the `bootstrap` binary
- Update the Lambda function code

**Note**: If you used `--full` flag in Phase 2, this step is already complete.

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

### CloudFormation stack in ROLLBACK_COMPLETE state

If a previous deployment failed, the stack may be in `ROLLBACK_COMPLETE` state.

**Solution**:
```bash
# Use the cleanup script
./deployments/cleanup-stack.sh dev

# Or manually delete the stack
aws cloudformation delete-stack --stack-name cloudops-dev --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name cloudops-dev --region us-east-1

# Then retry deployment
./deployments/deploy-stack.sh dev
```

### Bedrock model not enabled

If you see "AWS Bedrock Claude 3.5 Sonnet v2 is NOT enabled", you need to enable model access:

1. Go to AWS Console → Amazon Bedrock → Model Access
2. Click **Request model access**
3. Enable: **Anthropic Claude 3.5 Sonnet v2**
4. Wait 2-3 minutes for activation
5. Re-run deployment script

### Docker not running (when using --full flag)

If you see "Docker is not running":

1. Start Docker Desktop (or Docker daemon)
2. Verify: `docker info`
3. Re-run deployment

### Bot not responding

1. Check Lambda logs for errors: `aws logs tail /aws/lambda/cloudops-slack-handler-dev --follow`
2. Verify Slack tokens are stored in Parameter Store: `aws ssm get-parameter --name /cloudops/dev/slack-bot-token`
3. Check that bot is installed in workspace
4. Verify Slack app scopes are correct
5. Verify webhook URL is configured in Slack Event Subscriptions

### Container fails to start

1. Check ECS agent logs: `aws logs tail /ecs/cloudops-agent-dev --follow`
2. Verify Docker image exists in ECR
3. Verify DynamoDB tables exist and are accessible
4. Check IAM role has Bedrock permissions
5. Verify Bedrock model is enabled in the region

### Deployment fails with permission errors

Verify your AWS credentials have permissions for:
- CloudFormation (create/update/delete stacks)
- IAM (create roles and policies)
- VPC, EC2, ECS, Lambda, DynamoDB, Step Functions, ECR, API Gateway
- Parameter Store (read parameters)
- Bedrock (invoke model)

## Cleanup

To remove all resources:

```bash
# Use the cleanup script
./deployments/cleanup-stack.sh dev

# Or manually delete the stack
aws cloudformation delete-stack --stack-name cloudops-dev --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name cloudops-dev --region us-east-1
```

**Note**: The following resources are NOT automatically deleted:
- Parameter Store secrets (must delete manually if desired)
- CloudWatch log groups (subject to retention policy)
- ECR images older than the 10 most recent (managed by lifecycle policy)

## Next Steps

1. Implement the agent container with Claude API integration
2. Implement Lambda handler for Slack events
3. Test end-to-end flow
4. Add monitoring and alerting
5. Set up CI/CD for automated deployments
