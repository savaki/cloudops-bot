# Slack App Setup Guide

Complete guide to creating a Slack app and obtaining the required credentials for CloudOps Bot.

> **⚡ Quick Setup**: Use the [App Manifest method](SLACK_SETUP_WITH_MANIFEST.md) to create your app in 2 minutes instead of 10!

## What You Need

CloudOps Bot requires two Slack credentials:

1. **`SLACK_BOT_TOKEN`** - Bot User OAuth Token (starts with `xoxb-`)
2. **`SLACK_SIGNING_KEY`** - Signing Secret for webhook validation

## Step-by-Step Setup

### 1. Create a Slack App

1. Go to https://api.slack.com/apps
2. Click **"Create New App"**
3. Select **"From scratch"**
4. Enter:
   - **App Name**: `CloudOps Bot` (or your preferred name)
   - **Workspace**: Select your workspace
5. Click **"Create App"**

### 2. Configure OAuth Scopes

The bot needs specific permissions to read mentions and post messages.

1. In your app settings, go to **"OAuth & Permissions"** (left sidebar)
2. Scroll down to **"Bot Token Scopes"**
3. Click **"Add an OAuth Scope"** and add these scopes:

   **Required Scopes:**
   - `app_mentions:read` - Read when the bot is mentioned
   - `channels:history` - Read channel message history
   - `channels:read` - View basic channel info
   - `chat:write` - Send messages as the bot
   - `im:history` - Read direct messages
   - `users:read` - View users in workspace

   **Optional (for advanced features):**
   - `channels:manage` - Create/manage channels
   - `groups:read` - Access private channels (if needed)
   - `groups:write` - Manage private channels
   - `files:read` - Read uploaded files
   - `reactions:write` - Add emoji reactions

### 3. Install App to Workspace

1. Scroll to the top of **"OAuth & Permissions"** page
2. Click **"Install to Workspace"**
3. Review the permissions
4. Click **"Allow"**

### 4. Get Bot User OAuth Token

After installation:

1. You'll be redirected back to **"OAuth & Permissions"**
2. Find **"Bot User OAuth Token"** at the top
3. **Copy the token** - it starts with `xoxb-` (e.g., `xoxb-YOUR-BOT-TOKEN-HERE`)

   ⚠️ **Keep this secret!** This token has full bot permissions.

   ```bash
   # Save it temporarily
   export SLACK_BOT_TOKEN="xoxb-your-actual-token-here"
   ```

### 5. Get Signing Secret

1. Go to **"Basic Information"** (left sidebar)
2. Scroll down to **"App Credentials"**
3. Find **"Signing Secret"**
4. Click **"Show"** to reveal it
5. **Copy the secret** (e.g., `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`)

   ```bash
   # Save it temporarily
   export SLACK_SIGNING_KEY="your-signing-secret-here"
   ```

### 6. Enable Event Subscriptions (for webhook mode)

CloudOps Bot uses webhooks (API Gateway), not Socket Mode.

1. Go to **"Event Subscriptions"** (left sidebar)
2. Toggle **"Enable Events"** to **ON**
3. **Request URL**: You'll add this after deploying AWS infrastructure
   - Format: `https://your-api-gateway-url/slack/events`
   - Leave blank for now, you'll update this after deployment

4. Under **"Subscribe to bot events"**, add:
   - `app_mention` - When someone @mentions your bot

5. Click **"Save Changes"**

### 7. Customize App Appearance (Optional)

1. Go to **"Basic Information"**
2. Scroll to **"Display Information"**
3. Add:
   - **App name**: CloudOps Bot
   - **Short description**: AI-powered AWS troubleshooting assistant
   - **App icon**: Upload a custom icon
   - **Background color**: Choose a color

## Store Credentials in AWS

Once you have both credentials, store them securely in AWS Parameter Store.

### Using the Setup Script (Recommended)

```bash
./deployments/setup-secrets.sh dev \
  --slack-bot-token "${SLACK_BOT_TOKEN}" \
  --slack-signing-key "${SLACK_SIGNING_KEY}"
```

### Using AWS CLI Directly

```bash
ENV=dev

# Store Bot Token
aws ssm put-parameter \
  --name "/cloudops/${ENV}/slack-bot-token" \
  --value "${SLACK_BOT_TOKEN}" \
  --type SecureString \
  --overwrite

# Store Signing Secret
aws ssm put-parameter \
  --name "/cloudops/${ENV}/slack-signing-key" \
  --value "${SLACK_SIGNING_KEY}" \
  --type SecureString \
  --overwrite
```

### Verify Storage

```bash
# Check parameters exist
aws ssm get-parameter --name "/cloudops/dev/slack-bot-token" --query 'Parameter.Name'
aws ssm get-parameter --name "/cloudops/dev/slack-signing-key" --query 'Parameter.Name'
```

## Connect Slack to Your Deployment

After deploying CloudOps infrastructure to AWS:

### 1. Get Your Webhook URL

```bash
aws cloudformation describe-stacks \
  --stack-name cloudops-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text
```

This returns something like:
```
https://abc123def.execute-api.us-east-1.amazonaws.com/dev/slack/events
```

### 2. Update Slack Event Subscriptions

1. Go back to https://api.slack.com/apps
2. Select your app
3. Go to **"Event Subscriptions"**
4. Paste your webhook URL into **"Request URL"**
5. Slack will send a challenge request to verify your endpoint
6. If verification succeeds, you'll see a green checkmark ✅
7. Click **"Save Changes"**

### 3. Test the Bot

In your Slack workspace:

```
@CloudOps Bot hello
```

The bot should respond!

## Troubleshooting

### "invalid_auth" Error

**Problem**: Slack returns `invalid_auth` when bot tries to post messages.

**Solutions**:
- Verify token starts with `xoxb-`
- Check token is stored correctly in Parameter Store
- Reinstall app to workspace (OAuth & Permissions → Reinstall)
- Generate new token if old one expired

### Webhook Verification Fails

**Problem**: Slack can't verify your Request URL.

**Solutions**:
- Check Lambda function is deployed and responding
- Verify API Gateway is publicly accessible
- Check Lambda logs for errors: `aws logs tail /aws/lambda/cloudops-slack-handler-dev --follow`
- Ensure `SLACK_SIGNING_KEY` matches exactly

### Bot Doesn't Respond to Mentions

**Problem**: @mention doesn't trigger the bot.

**Solutions**:
- Check Event Subscriptions has `app_mention` event
- Verify Request URL is correct and verified
- Check bot has `app_mentions:read` scope
- Look at Lambda logs for incoming events

### Rate Limiting

**Problem**: Slack returns `rate_limited` errors.

**Solutions**:
- Implement exponential backoff in your code
- Cache Slack API responses when possible
- Reduce API calls by batching operations

## Security Best Practices

1. **Never commit tokens to git**
   ```bash
   # Add to .gitignore
   .env
   *.env
   secrets.sh
   ```

2. **Rotate tokens periodically**
   - Generate new tokens every 90 days
   - Update in Parameter Store
   - Redeploy Lambda function

3. **Use Parameter Store SecureString**
   - Tokens are encrypted at rest
   - Access controlled by IAM
   - Audit access with CloudTrail

4. **Limit token scopes**
   - Only add OAuth scopes you actually need
   - Review scopes regularly
   - Remove unused scopes

5. **Monitor for unusual activity**
   - Check CloudWatch logs for unexpected calls
   - Set up alarms for error rates
   - Monitor Slack app dashboard

## Credential Reference

| Credential | Where to Find | Format | Storage Location |
|------------|---------------|--------|------------------|
| **Bot Token** | OAuth & Permissions → Bot User OAuth Token | `xoxb-...` | `/cloudops/{env}/slack-bot-token` |
| **Signing Secret** | Basic Information → App Credentials | 32 hex chars | `/cloudops/{env}/slack-signing-key` |
| **Webhook URL** | AWS CloudFormation outputs | `https://...` | Slack Event Subscriptions |

## Next Steps

1. ✅ Create Slack app
2. ✅ Get Bot Token and Signing Secret
3. ✅ Store in AWS Parameter Store
4. ⏭️ Deploy CloudOps infrastructure: `./deployments/deploy-stack.sh dev`
5. ⏭️ Configure webhook URL in Slack
6. ⏭️ Test the bot: `@CloudOps Bot hello`

## Resources

- **Slack API Documentation**: https://api.slack.com/docs
- **OAuth Scopes Reference**: https://api.slack.com/scopes
- **Event Subscriptions**: https://api.slack.com/events-api
- **Slack App Management**: https://api.slack.com/apps
