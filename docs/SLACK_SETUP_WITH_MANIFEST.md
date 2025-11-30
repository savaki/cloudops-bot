# Slack Setup with App Manifest (2 Minutes!)

Use the app manifest to create your Slack app in seconds instead of clicking through settings.

## Quick Setup (2 Minutes)

### 1. Create App from Manifest

1. Go to https://api.slack.com/apps
2. Click **"Create New App"**
3. Select **"From an app manifest"** (not "From scratch")
4. Choose your workspace
5. Select **"YAML"** tab
6. Copy and paste the entire contents of `slack-app-manifest.yaml`
7. Click **"Next"**
8. Review the configuration
9. Click **"Create"**

That's it! All OAuth scopes and settings are pre-configured.

### 2. Install to Workspace

1. Click **"Install to Workspace"**
2. Review permissions
3. Click **"Allow"**

### 3. Get Your Credentials

**Bot Token:**
```
OAuth & Permissions → Bot User OAuth Token
Copy the token (starts with xoxb-)
```

**Signing Secret:**
```
Basic Information → App Credentials → Signing Secret
Click "Show" → Copy
```

### 4. Store in AWS

```bash
# Export credentials
export SLACK_BOT_TOKEN="xoxb-your-token-here"
export SLACK_SIGNING_KEY="your-signing-secret-here"

# Store in Parameter Store
./deployments/setup-secrets.sh dev \
  --slack-bot-token "${SLACK_BOT_TOKEN}" \
  --slack-signing-key "${SLACK_SIGNING_KEY}"
```

### 5. Deploy AWS Infrastructure

```bash
# Deploy the stack
./deployments/deploy-stack.sh dev --full

# Get the webhook URL
aws cloudformation describe-stacks \
  --stack-name cloudops-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text
```

### 6. Configure Webhook URL

1. Go back to https://api.slack.com/apps
2. Select your app
3. Go to **"Event Subscriptions"**
4. Paste your webhook URL (from step 5) into **"Request URL"**
5. Wait for the green checkmark ✅ (Slack verifies the endpoint)
6. Click **"Save Changes"**

### 7. Test It!

In Slack:
```
@CloudOps Bot hello
```

## What the Manifest Configures

✅ App name: "CloudOps Bot"
✅ Description and branding
✅ OAuth scopes (6 scopes)
✅ Event subscription for `app_mention`
✅ Bot user settings
✅ App Home tab

## Customizing the Manifest

You can edit `slack-app-manifest.yaml` to:

**Change app name:**
```yaml
display_information:
  name: My Custom Bot Name
```

**Add more OAuth scopes:**
```yaml
oauth_config:
  scopes:
    bot:
      - app_mentions:read
      - chat:write
      - your_additional_scope  # Add here
```

**Add more event subscriptions:**
```yaml
settings:
  event_subscriptions:
    bot_events:
      - app_mention
      - message.im  # Add direct messages
```

## Manifest vs Manual Setup

| Method | Time | Complexity | Reproducible |
|--------|------|------------|--------------|
| **Manifest** | 2 min | ⭐ Easy | ✅ Yes - share the file |
| **Manual** | 10 min | ⭐⭐⭐ Complex | ❌ No - manual steps |

**Benefits of Manifest:**
- Create multiple apps instantly (dev/staging/prod)
- Version control your Slack app configuration
- Share exact configuration with team
- No clicking through UI
- Impossible to forget a scope

## Troubleshooting

**"Invalid manifest" error:**
- Check YAML syntax (indentation matters!)
- Ensure all required fields are present
- Remove any commented lines if causing issues

**Request URL verification fails:**
- Make sure AWS infrastructure is deployed first
- Check Lambda function responds to challenge requests
- Verify API Gateway is publicly accessible

**Bot doesn't have permission to post:**
- Verify `chat:write` scope is in the manifest
- Reinstall the app to workspace
- Check bot token is fresh (not expired)

## Pro Tips

### Multiple Environments

Create separate apps for each environment:

```bash
# Dev
slack-app-manifest-dev.yaml   → CloudOps Bot (Dev)

# Staging
slack-app-manifest-staging.yaml → CloudOps Bot (Staging)

# Production
slack-app-manifest-prod.yaml    → CloudOps Bot
```

### Update Existing App

1. Go to https://api.slack.com/apps
2. Select your app
3. Go to **"App Manifest"** (left sidebar)
4. Edit the YAML
5. Click **"Save Changes"**

### Export Current Config

If you already have an app configured manually:

1. Go to your app settings
2. Click **"App Manifest"** (left sidebar)
3. Copy the YAML
4. Save to `slack-app-manifest.yaml`

## Complete Workflow

```bash
# 1. Create app from manifest (2 min, via Slack website)

# 2. Store credentials
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_SIGNING_KEY="..."
./deployments/setup-secrets.sh dev \
  --slack-bot-token "${SLACK_BOT_TOKEN}" \
  --slack-signing-key "${SLACK_SIGNING_KEY}"

# 3. Deploy infrastructure
./deployments/deploy-stack.sh dev --full

# 4. Get webhook URL
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name cloudops-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text)

echo "Add this to Slack Event Subscriptions Request URL:"
echo "${WEBHOOK_URL}"

# 5. Manually add webhook URL in Slack (30 seconds)

# 6. Test
# In Slack: @CloudOps Bot hello
```

## Next Steps

- ✅ Create Slack app from manifest
- ✅ Get Bot Token and Signing Secret
- ✅ Store credentials in AWS
- ⏭️ Deploy infrastructure
- ⏭️ Configure webhook URL
- ⏭️ Test the bot

## Resources

- **Slack App Manifest Documentation**: https://api.slack.com/reference/manifests
- **Manifest Schema**: https://api.slack.com/reference/manifests#schema
- **OAuth Scopes Reference**: https://api.slack.com/scopes
