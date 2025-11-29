# CloudOps Bot - Quick Start Guide

Get up and running in 30 minutes.

## 1. Prerequisites (5 min)

```bash
# Verify you have the tools
go version          # Should be 1.21+
aws --version       # AWS CLI configured
docker --version    # Docker installed
git --version       # Git installed
```

## 2. Create Slack App (5 min)

1. Go to https://api.slack.com/apps
2. "Create New App" → "From scratch"
3. Name: `CloudOps`, Workspace: yours
4. Go to "Socket Mode" → Enable it → Generate App-Level Token (copy `xapp-...`)
5. Go to "OAuth & Permissions" → Add scopes:
   - `app_mentions:read`, `channels:manage`, `channels:read`, `chat:write`, `groups:write`, `groups:read`, `im:history`, `users:read`
6. "Install to Workspace" (copy Bot Token `xoxb-...`)

## 3. Set Up AWS (5 min)

```bash
# Store Slack tokens (replace with your values)
aws secretsmanager create-secret \
  --name slack-bot-token \
  --secret-string "xoxb-YOUR-TOKEN"

aws secretsmanager create-secret \
  --name slack-app-token \
  --secret-string "xapp-YOUR-TOKEN"

aws secretsmanager create-secret \
  --name slack-signing-key \
  --secret-string "YOUR-SIGNING-SECRET"
```

## 4. Deploy Infrastructure (10 min)

```bash
# Use the Makefile for easy deployment
make deploy-all ENV=dev

# Or manually:
make deploy-vpc ENV=dev
make deploy-dynamodb ENV=dev
make deploy-iam ENV=dev
make deploy-ecr ENV=dev
make deploy-ecs ENV=dev
make deploy-stepfunc ENV=dev
make deploy-lambda ENV=dev
make deploy-apigateway ENV=dev  # Optional
```

## 5. Implement Your Agent (varies)

Edit `cmd/agent/main.go` and implement:

```go
// 1. Initialize Slack Socket Mode
// 2. Load conversation from DynamoDB
// 3. Send messages to Claude API
// 4. Post responses back to Slack
// 5. Update DynamoDB heartbeat
```

See `IMPLEMENTATION_GUIDE.md` for detailed instructions.

## 6. Build & Deploy (5 min)

```bash
# Build and push agent container
./deployments/build-agent.sh dev latest

# Build and package Lambda
./deployments/package-lambda.sh dev slack-handler
```

## 7. Test in Slack

```bash
# Check logs
make logs-lambda ENV=dev  # In one terminal
make logs-agent ENV=dev   # In another

# In Slack:
# @CloudOps hello
```

## Common Commands

```bash
# View logs
make logs-lambda
make logs-agent
make logs-errors

# Rebuild everything
make clean && make build-agent && make package-lambda

# Full redeploy
make clean-all && make deploy-all && make build-agent && make package-lambda

# Check stack status
aws cloudformation describe-stacks --stack-name cloudops-vpc-dev --query 'Stacks[0].StackStatus'
```

## Project Structure

- `cmd/agent/` - Your agent implementation (Claude API)
- `cmd/slack-handler/` - Lambda handler (stubs provided)
- `pkg/` - Supporting libraries
- `infrastructure/cloudformation/` - AWS infrastructure
- `deployments/` - Docker and build scripts
- `IMPLEMENTATION_GUIDE.md` - Detailed implementation docs
- `DEPLOYMENT.md` - Full deployment guide

## Troubleshooting

**Bot not responding?**
```bash
# Check Lambda logs
aws logs tail /aws/lambda/cloudops-slack-handler-dev --follow

# Check agent logs
aws logs tail /ecs/cloudops-agent-dev --follow
```

**Container failing?**
- Check ECS logs: `aws logs tail /ecs/cloudops-agent-dev --follow`
- Verify DynamoDB table: `aws dynamodb list-tables | grep cloudops`
- Check IAM role permissions

**CloudFormation failed?**
```bash
# See what went wrong
aws cloudformation describe-stack-events \
  --stack-name cloudops-vpc-dev \
  --query 'StackEvents[0:5]'
```

## Architecture

```
Slack (@mention)
    ↓
Lambda (validate, create channel)
    ↓
DynamoDB (save conversation)
    ↓
Step Functions (orchestrate)
    ↓
ECS Fargate (your agent)
    ↓
Claude API (your implementation)
    ↓
Slack (responses)
```

## Next Steps

1. **Read** `IMPLEMENTATION_GUIDE.md` for detailed agent implementation
2. **Implement** your Claude API integration in `cmd/agent/main.go`
3. **Test** locally with mock data
4. **Deploy** using `./deployments/build-agent.sh dev`
5. **Monitor** logs in CloudWatch

## Resources

- [IMPLEMENTATION_GUIDE.md](./IMPLEMENTATION_GUIDE.md) - Detailed implementation
- [DEPLOYMENT.md](./DEPLOYMENT.md) - Full deployment guide
- [README.md](./README.md) - Overview
- [Slack API Docs](https://api.slack.com/)
- [Claude API Docs](https://docs.anthropic.com/)

## Support

Check CloudWatch logs for detailed error messages:
- Lambda: `/aws/lambda/cloudops-slack-handler-dev`
- Agent: `/ecs/cloudops-agent-dev`

---

That's it! You're ready to build your cloud ops bot. Happy coding!
