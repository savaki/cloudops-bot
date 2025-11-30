# CloudOps Bot - Required Secrets

This document lists all required secrets and where they're used.

## Required Secrets

### 1. Slack Bot Token
**Parameter Name**: `/cloudops/{env}/slack-bot-token`
**Format**: `xoxb-...`
**Used By**: Lambda Handler, ECS Agent
**Purpose**:
- Post messages to Slack channels
- Retrieve user information
- Read channel data

**How to Get**:
1. Go to https://api.slack.com/apps
2. Select your app
3. Navigate to "OAuth & Permissions"
4. Find "Bot User OAuth Token"

### 2. Slack Signing Secret
**Parameter Name**: `/cloudops/{env}/slack-signing-key`
**Format**: Random hex string (e.g., `abc123def456...`)
**Used By**: Lambda Handler
**Purpose**:
- Validate webhook requests from Slack
- Prevent unauthorized access to the webhook endpoint

**How to Get**:
1. Go to https://api.slack.com/apps
2. Select your app
3. Navigate to "Basic Information"
4. Find "Signing Secret" under "App Credentials"

## ~~Claude API Key~~ NO LONGER NEEDED! 🎉

**We now use AWS Bedrock instead of the Claude API**, which means:
- ✅ **No API key required** - Uses AWS IAM permissions instead
- ✅ **Lower cost** - Bedrock pricing is often more economical for production use
- ✅ **Better security** - No API keys to manage or rotate
- ✅ **Integrated billing** - Part of your AWS bill

## Bedrock Model Access

Instead of an API key, you need to enable Bedrock model access:

1. Go to https://console.aws.amazon.com/bedrock/
2. Navigate to "Model access" in the left sidebar
3. Click "Modify model access"
4. Enable **"Claude 3.5 Sonnet v2"** from Anthropic
5. Click "Save changes" and wait for approval (usually instant)

**Model ID**: `anthropic.claude-3-5-sonnet-20241022-v2:0`

The deployment script will automatically verify you have access to this model!

## Setup Instructions

### Automated Setup (Recommended)

```bash
# Interactive mode - prompts for Slack tokens only
./deployments/setup-secrets.sh dev --interactive
```

### Manual Setup

```bash
# Slack Bot Token
aws ssm put-parameter \
  --name /cloudops/dev/slack-bot-token \
  --value "xoxb-your-actual-token" \
  --type SecureString

# Slack Signing Secret
aws ssm put-parameter \
  --name /cloudops/dev/slack-signing-key \
  --value "your-actual-signing-secret" \
  --type SecureString
```

## Verification

Check that all secrets are configured:

```bash
# Check parameters exist
aws ssm get-parameter --name /cloudops/dev/slack-bot-token --with-decryption
aws ssm get-parameter --name /cloudops/dev/slack-signing-key --with-decryption
```

Or use the setup script:

```bash
./deployments/setup-secrets.sh dev
```

## Security Best Practices

1. **Never commit secrets to git** - They're in `.gitignore` but double-check
2. **Use different secrets per environment** - dev, staging, prod should have separate values
3. **Rotate secrets regularly** - Update with `--update` flag
4. **Use least privilege** - Each component only has access to secrets it needs
5. **Monitor access** - Enable CloudTrail logging for Parameter Store access

## Cost

**Parameter Store (Standard)**: **FREE**
- No charge for standard parameters
- Up to 10,000 parameters per account
- 4KB max size per parameter (our secrets are well under this)

**AWS Bedrock**: Pay per use
- Input: ~$0.003 per 1K tokens
- Output: ~$0.015 per 1K tokens
- No minimum, no monthly fees
- Much cheaper than Claude API at scale

## IAM Permissions

### Lambda Handler
- ✅ `/cloudops/{env}/slack-bot-token` - Posts acknowledgment messages
- ✅ `/cloudops/{env}/slack-signing-key` - Validates webhooks

### ECS Agent
- ✅ `/cloudops/{env}/slack-bot-token` - Posts conversation responses
- ✅ `bedrock:InvokeModel` - Calls Claude via Bedrock (IAM-based, no API key!)

### Principle of Least Privilege
Each component only has permissions for the secrets it actually uses.

## Troubleshooting

### Error: "Parameter not found"
**Cause**: Slack secrets not configured in Parameter Store

**Solution**:
```bash
./deployments/setup-secrets.sh dev --interactive
```

### Error: "Access Denied" (Bedrock)
**Cause**: Bedrock model access not enabled

**Solution**:
1. Go to AWS Bedrock console → Model Access
2. Click "Modify model access"
3. Enable "Claude 3.5 Sonnet v2"
4. Wait for approval (usually instant)
5. Verify: `aws bedrock list-foundation-models --region us-east-1 | grep claude-3-5-sonnet`

### Error: "Access Denied" (Parameter Store)
**Cause**: Insufficient IAM permissions

**Solution**:
Ensure your AWS credentials have these permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DescribeParameters"
    ],
    "Resource": "arn:aws:ssm:*:*:parameter/cloudops/*"
  }]
}
```

### Error: "Invalid Slack token"
**Cause**: Token revoked or incorrect scope

**Solution**:
1. Go to https://api.slack.com/apps
2. Reinstall app to workspace
3. Copy new Bot User OAuth Token
4. Update parameter:
```bash
./deployments/setup-secrets.sh dev --update \
  --slack-bot-token "xoxb-new-token"
```

### Error: "Region not supported"
**Cause**: Bedrock not available in your AWS region

**Solution**:
Use a supported region:
- us-east-1 (recommended)
- us-west-2
- eu-central-1
- ap-southeast-1
- ap-northeast-1

Set region before deploying:
```bash
export AWS_REGION=us-east-1
./deployments/deploy-stack.sh dev
```

### Secret Rotation
**Best Practice**: Rotate secrets every 90 days

**Process**:
1. Generate new token in Slack
2. Update Parameter Store:
   ```bash
   ./deployments/setup-secrets.sh dev --update \
     --slack-bot-token "xoxb-new-token"
   ```
3. Test immediately - no redeployment needed (Lambda reads from Parameter Store on each invocation)

### View Current Values
```bash
# View Slack bot token
aws ssm get-parameter \
  --name /cloudops/dev/slack-bot-token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text

# View Slack signing key
aws ssm get-parameter \
  --name /cloudops/dev/slack-signing-key \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

### Delete All Secrets (Cleanup)
```bash
aws ssm delete-parameter --name /cloudops/dev/slack-bot-token
aws ssm delete-parameter --name /cloudops/dev/slack-signing-key
```

## Migration from Claude API

If you previously used the Claude API:

1. **Remove the Claude API key parameter** (no longer needed):
   ```bash
   aws ssm delete-parameter --name /cloudops/dev/claude-api-key
   ```

2. **Enable Bedrock model access** (see above)

3. **Redeploy the stack** - It will use Bedrock automatically

That's it! No code changes needed.
