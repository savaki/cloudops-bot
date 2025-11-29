# CloudOps Bot

LLM-enabled chatbot to troubleshoot cloud issues via Slack.

## Features

- **Slack Integration**: Webhook-based events via API Gateway
- **Hybrid Architecture**: Lambda for initiation, on-demand ECS tasks for conversations
- **AWS Cloud Access**: Read-only access to EC2, ECS, RDS, CloudWatch, Lambda, and more
- **Claude AI Integration**: Powered by Claude API for intelligent troubleshooting
- **Tool Calling**: ECS tasks can execute AWS SDK operations with read-only permissions
- **Conversation History**: Full message history stored in DynamoDB
- **Auto Timeout**: 30-minute inactivity timeout with graceful shutdown
- **Production Ready**: CloudFormation IaC, comprehensive logging, error handling

## Architecture

**Hybrid Serverless + Container Architecture**

```
┌─────────────────┐
│     Slack       │
│   (Webhooks)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  API Gateway    │
│   (HTTP POST)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Lambda Handler  │
│ • Signature Val │
│ • URL Verify    │
│ • Create Conv   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Step Functions  │
│ • Spawn Task    │
│ • Monitor       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ECS Fargate    │
│ • Claude API    │
│ • Tool Calling  │
│ • AWS SDK (RO)  │
│ • Slack Posts   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   DynamoDB      │
│ • Conversations │
│ • History       │
└─────────────────┘
```

**Key Design Decisions:**
- **API Gateway**: Slack webhooks delivered via HTTP POST (no Socket Mode)
- **Lambda**: Lightweight initiation point, spawns ECS tasks via Step Functions
- **ECS Tasks**: On-demand containers with read-only AWS permissions for tool calling
- **Step Functions**: Orchestrates task lifecycle (spawn, monitor, cleanup)
- **DynamoDB**: Persistent conversation state and message history

## Prerequisites

### Required

- **Go 1.21 or later** - https://golang.org/dl
- **Docker** - For building container images
- **AWS CLI v2** - For deployment (https://aws.amazon.com/cli)
- **AWS Account** with appropriate permissions
- **Make** - Build tool (installed by default on macOS/Linux)
- **Slack Workspace** - With admin access to create apps

### Environment Setup

Ensure these tools are in your PATH:

```bash
# Check Go version
go version                          # Should be 1.21+

# Check Docker
docker --version                    # Should be 4.0+

# Check AWS CLI
aws --version                       # Should be 2.0+

# Check Make
make --version                      # Should be 4.0+
```

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/savaki/cloudops-bot.git
cd cloudops-bot
```

### 2. Download Dependencies

```bash
# Download Go dependencies
go mod download

# Verify dependencies
go mod tidy
```

### 3. Build Locally (Optional)

```bash
# Build Lambda handler
./deployments/package-lambda.sh dev slack-handler

# Build agent container (requires Docker)
./deployments/build-agent.sh dev latest
```

## Configuration

### Environment Variables

The application requires these environment variables:

#### Core Slack Configuration

```bash
export SLACK_BOT_TOKEN=xoxb-your-bot-token
export SLACK_SIGNING_KEY=your-signing-key
```

#### AWS Configuration

```bash
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
```

#### Application Configuration

```bash
export ENVIRONMENT=dev                          # or 'prod'
export CONVERSATIONS_TABLE=cloudops-conversations
export CONVERSATION_HISTORY_TABLE=cloudops-conversation-history
export INACTIVITY_TIMEOUT_MINUTES=30            # Default: 30 minutes
export STEP_FUNCTION_ARN=arn:aws:states:...     # Set during deployment
export ECS_CLUSTER_NAME=cloudops-cluster
```

### Slack App Setup

1. **Create Slack App**:
   - Go to https://api.slack.com/apps
   - Click "Create New App" → "From scratch"
   - Name: `CloudOps Bot`
   - Workspace: Select your workspace

2. **OAuth Scopes** (Bot Token Scopes):
   - `app_mentions:read` - Receive mentions
   - `chat:write` - Send messages
   - `channels:read` - Read public channels
   - `users:read` - Get user info

3. **Event Subscriptions**:
   - Enable Events
   - Request URL: `https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com/prod/slack/events`
   - Subscribe to bot events: `app_mention`
   - **Important**: Deploy API Gateway first, then configure the Request URL

4. **Install App**:
   - Install to your workspace
   - Copy Bot User OAuth Token (starts with `xoxb-`)

5. **Retrieve Signing Secret**:
   - Settings → Basic Information → App Credentials
   - Copy "Signing Secret" (used for webhook signature validation)

### Store Secrets in AWS Systems Manager Parameter Store

Using Parameter Store (FREE) instead of Secrets Manager.

**Required Secrets (ONLY 2!):**
1. **Slack Bot Token** (`/cloudops/dev/slack-bot-token`) - OAuth token from Slack app
2. **Slack Signing Secret** (`/cloudops/dev/slack-signing-key`) - Webhook validation key

**~~Claude API Key~~** - **NOT NEEDED!** We use AWS Bedrock instead (IAM-based, no API keys!)

📖 [Detailed secrets documentation](docs/SECRETS.md)

**Option 1 - Automated (Recommended):**
```bash
# Interactive mode - prompts for values
./deployments/setup-secrets.sh dev --interactive

# Command line arguments
./deployments/setup-secrets.sh dev \
  --slack-bot-token xoxb-your-token \
  --slack-signing-key your-signing-secret
```

**Option 2 - Manual:**
```bash
# Create parameters manually (only 2 needed!)
aws ssm put-parameter \
  --name /cloudops/dev/slack-bot-token \
  --value xoxb-your-token \
  --type SecureString

aws ssm put-parameter \
  --name /cloudops/dev/slack-signing-key \
  --value your-signing-secret \
  --type SecureString
```

### Enable Bedrock Model Access

**One-time setup**: Enable Claude 3.5 Sonnet in AWS Bedrock:

1. Go to https://console.aws.amazon.com/bedrock/
2. Click "Model access" → "Modify model access"
3. Enable **"Claude 3.5 Sonnet v2"** from Anthropic
4. Click "Save changes" (approval is usually instant)

The deployment script will verify this automatically!

## Development

### Local Setup

1. **Set environment variables** (create `.env.local`):

```bash
cat > .env.local << 'EOF'
export SLACK_BOT_TOKEN=xoxb-your-token
export SLACK_SIGNING_KEY=your-signing-secret
export CLAUDE_API_KEY=sk-ant-your-key
export AWS_REGION=us-east-1
export ENVIRONMENT=dev
export INACTIVITY_TIMEOUT_MINUTES=30
export CONVERSATIONS_TABLE=cloudops-conversations-dev
export CONVERSATION_HISTORY_TABLE=cloudops-conversation-history-dev
EOF

source .env.local
```

2. **Install dependencies**:

```bash
go mod download
go mod tidy
```

3. **Run tests**:

```bash
go test ./...
go test -cover ./...
```

4. **Format code**:

```bash
go fmt ./...
```

5. **Run linters**:

```bash
go vet ./...
golangci-lint run ./...     # If installed
```

### Project Structure

```
cloudops-bot/
├── cmd/
│   ├── agent/              # ECS agent container
│   │   └── main.go
│   ├── slack-handler/      # Lambda handler
│   │   └── main.go
│   └── failure-notifier/   # Error notifications (stub)
├── pkg/
│   ├── config/             # Environment configuration
│   ├── dynamodb/           # DynamoDB operations
│   ├── handler/            # Slack event handling
│   ├── models/             # Data types
│   ├── slack/              # Slack client wrapper
│   └── stepfunctions/      # Step Functions orchestration
├── infrastructure/
│   └── cloudformation/
│       └── cloudops-stack.yaml  # Complete single-file CloudFormation template
├── deployments/
│   ├── Dockerfile.agent
│   ├── build-agent.sh
│   └── package-lambda.sh
├── Makefile                # Build/deploy targets
└── go.mod
```

### Code Organization

**Command Packages** (`cmd/`):
- Entry points for Lambda handler and ECS agent
- Contains business logic specific to each component

**Domain Packages** (`pkg/`):
- `config`: Environment variable loading and validation
- `models`: Data structures for conversations and messages
- `dynamodb`: DynamoDB repository implementation
- `slack`: Slack API client wrapper
- `handler`: Slack event parsing and business logic
- `stepfunctions`: AWS Step Functions orchestration

**Infrastructure** (`infrastructure/`):
- CloudFormation templates for AWS resources
- VPC, DynamoDB, IAM, ECS, Lambda, Step Functions

## Deployment

### Prerequisites for Deployment

- AWS IAM permissions for CloudFormation, Lambda, ECS, DynamoDB, ECR, etc.
- Slack tokens configured in AWS Secrets Manager
- Docker Hub or ECR access for container images

### Quick Deployment (Recommended)

Use the provided deployment script to deploy the entire stack at once:

```bash
# Deploy complete infrastructure (uses default VPC)
./deployments/deploy-stack.sh dev

# Or specify custom networking
./deployments/deploy-stack.sh dev "subnet-abc123,subnet-def456" sg-xyz789
```

The script will:
1. ✅ Create all infrastructure resources in a single CloudFormation stack
2. ✅ Automatically detect default VPC and subnets
3. ✅ Create or reuse security groups
4. ✅ Validate that required secrets exist
5. ✅ Display webhook URL for Slack configuration

### Manual Deployment (Advanced)

If you prefer manual control:

```bash
ENVIRONMENT=dev
AWS_REGION=us-east-1
SUBNET_IDS="subnet-abc123,subnet-def456"
SECURITY_GROUP_ID="sg-xyz789"

# Deploy the complete stack
aws cloudformation create-stack \
  --stack-name cloudops-${ENVIRONMENT} \
  --template-body file://infrastructure/cloudformation/cloudops-stack.yaml \
  --parameters \
    ParameterKey=Environment,ParameterValue=${ENVIRONMENT} \
    ParameterKey=SubnetIds,ParameterValue=\"${SUBNET_IDS}\" \
    ParameterKey=SecurityGroupId,ParameterValue=${SECURITY_GROUP_ID} \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ${AWS_REGION}

# Wait for stack creation
aws cloudformation wait stack-create-complete \
  --stack-name cloudops-${ENVIRONMENT} \
  --region ${AWS_REGION}
```

### Post-Deployment Steps

After the stack is created:

```bash
ENVIRONMENT=dev

# 1. Build and push the agent Docker image
./deployments/build-agent.sh ${ENVIRONMENT}

# 2. Package and deploy Lambda function
./deployments/package-lambda.sh ${ENVIRONMENT} slack-handler

# 3. Get the webhook URL for Slack
aws cloudformation describe-stacks \
  --stack-name cloudops-${ENVIRONMENT} \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text
```

## Testing

### Run All Tests

```bash
go test ./...
```

### Run Tests with Coverage

```bash
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### Test Specific Package

```bash
go test -v ./pkg/handler
go test -v ./pkg/dynamodb
```

## Troubleshooting

### Issue: "slack.EventsAPIEvent undefined"
This is a build/version issue. Ensure you're using compatible slack-go/slack version.

### Issue: "Missing AWS credentials"
Ensure AWS credentials are set:
```bash
aws sts get-caller-identity
```

### Issue: Lambda timeout
Increase Lambda timeout in CloudFormation template (default: 60s)

### Issue: DynamoDB connection errors
Verify DynamoDB tables exist and IAM role has permissions

### Issue: Slack webhook validation failures
Verify `SLACK_SIGNING_KEY` matches the Signing Secret from Slack app settings

### Issue: ECS task fails to start
Check CloudWatch Logs for ECS tasks at `/ecs/cloudops-agent-{environment}`
Verify ECR image exists and task role has necessary permissions

## Monitoring

### CloudWatch Logs

```bash
# Lambda handler logs
aws logs tail /aws/lambda/cloudops-slack-handler-dev --follow

# ECS agent logs
aws logs tail /ecs/cloudops-agent-dev --follow

# Step Functions execution history
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:region:account:execution:cloudops-conversation-dev:conv-123
```

### CloudWatch Metrics

- Lambda invocations and errors
- ECS task count and CPU/memory
- DynamoDB read/write capacity
- Step Function executions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test locally
4. Ensure `go fmt`, `go vet`, and tests pass
5. Submit a pull request

## License

MIT

## Support

For issues and questions, please open a GitHub issue.

## Roadmap

- [ ] Additional cloud provider support (Azure, GCP)
- [ ] Advanced authentication (OAuth, SAML)
- [ ] Custom prompt templates
- [ ] Slack thread support
- [ ] Conversation analytics
- [ ] Multi-workspace support

## Next Steps

1. **Set up Slack App** (see Configuration section)
   - Create app at https://api.slack.com/apps
   - Configure OAuth scopes and event subscriptions
   - Copy Bot Token and Signing Secret

2. **Store Secrets** in AWS Systems Manager Parameter Store (FREE!)
   ```bash
   ./deployments/setup-secrets.sh dev --interactive
   ```
   Stores:
   - Slack Bot Token (`/cloudops/dev/slack-bot-token`)
   - Slack Signing Key (`/cloudops/dev/slack-signing-key`)
   - Claude API Key (`/cloudops/dev/claude-api-key`)

3. **Deploy Infrastructure** (single command)
   ```bash
   ./deployments/deploy-stack.sh dev
   ```
   This deploys all resources:
   - DynamoDB tables
   - IAM roles
   - ECR repository
   - ECS cluster and task definition
   - Step Functions state machine
   - Lambda handler
   - API Gateway

4. **Implement Agent Logic** in `cmd/agent/main.go`
   - Message polling or webhook subscription
   - Claude API integration with conversation history
   - AWS SDK tool calling (EC2, RDS, CloudWatch queries)
   - Response posting to Slack
   - Inactivity timeout and graceful shutdown

5. **Configure Slack Webhook**
   - Copy API Gateway URL from CloudFormation outputs
   - Add Request URL in Slack app Event Subscriptions
   - Verify URL with Slack challenge

6. **Test End-to-End**
   - Mention bot in Slack channel: `@CloudOps Bot help`
   - Verify Lambda spawns ECS task
   - Check CloudWatch Logs for agent execution
   - Confirm bot responds in Slack
