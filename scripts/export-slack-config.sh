#!/bin/bash
set -e

# Export Slack app configuration from an existing app using Slack API
# Usage: ./scripts/export-slack-config.sh <app-id> [output-file]
#
# Requirements:
#   - SLACK_USER_TOKEN environment variable (user token with admin.apps:read scope)
#   - Or use the web UI: Your App → App Manifest → Copy YAML

APP_ID=${1}
OUTPUT_FILE=${2:-slack-app-manifest-exported.yaml}

if [ -z "$APP_ID" ]; then
  echo "Usage: $0 <app-id> [output-file]"
  echo ""
  echo "Find your app ID:"
  echo "  1. Go to https://api.slack.com/apps"
  echo "  2. Select your app"
  echo "  3. Look for 'App ID' in Basic Information"
  echo ""
  echo "Example: $0 A1234567890"
  echo ""
  echo "Alternative (easier):"
  echo "  1. Go to https://api.slack.com/apps"
  echo "  2. Select your app"
  echo "  3. Click 'App Manifest' in sidebar"
  echo "  4. Copy the YAML"
  echo "  5. Save to ${OUTPUT_FILE}"
  echo ""
  exit 1
fi

if [ -z "$SLACK_USER_TOKEN" ]; then
  echo "======================================================================"
  echo "SLACK_USER_TOKEN not set"
  echo "======================================================================"
  echo ""
  echo "To export via API, you need a user token with admin.apps:read scope."
  echo ""
  echo "Easier method (recommended):"
  echo "  1. Go to https://api.slack.com/apps"
  echo "  2. Select your app (ID: ${APP_ID})"
  echo "  3. Click 'App Manifest' in the sidebar"
  echo "  4. Copy the YAML from the editor"
  echo "  5. Paste into ${OUTPUT_FILE}"
  echo ""
  echo "API method (advanced):"
  echo "  1. Create a user token at https://api.slack.com/apps/${APP_ID}/oauth"
  echo "  2. Add 'admin.apps:read' scope"
  echo "  3. Install to workspace"
  echo "  4. export SLACK_USER_TOKEN='xoxp-...'"
  echo "  5. Re-run this script"
  echo ""
  exit 1
fi

echo "======================================================================"
echo "Exporting Slack App Configuration"
echo "======================================================================"
echo "App ID: ${APP_ID}"
echo "Output: ${OUTPUT_FILE}"
echo ""

echo "Fetching app manifest..."
RESPONSE=$(curl -s -X POST https://slack.com/api/apps.manifest.export \
  -H "Authorization: Bearer ${SLACK_USER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\": \"${APP_ID}\"}")

# Check if request was successful
if echo "$RESPONSE" | jq -e '.ok == true' > /dev/null 2>&1; then
  echo "✅ Manifest retrieved"

  # Extract and save the manifest
  echo "$RESPONSE" | jq -r '.manifest' > "${OUTPUT_FILE}"

  echo ""
  echo "======================================================================"
  echo "✅ Manifest Exported"
  echo "======================================================================"
  echo "File: ${OUTPUT_FILE}"
  echo ""
  echo "Preview:"
  echo "----------------------------------------------------------------------"
  head -20 "${OUTPUT_FILE}"
  echo "..."
  echo "----------------------------------------------------------------------"
  echo ""
else
  ERROR=$(echo "$RESPONSE" | jq -r '.error // "Unknown error"')
  echo "❌ Failed to export manifest: ${ERROR}"
  echo ""
  echo "Response:"
  echo "$RESPONSE" | jq .
  echo ""
  echo "Use the web UI instead:"
  echo "  https://api.slack.com/apps/${APP_ID}/app-manifest"
  exit 1
fi
