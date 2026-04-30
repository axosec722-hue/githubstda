#!/bin/bash

# ─── Config ───────────────────────────────────────────────────────────────────

ENCODED_WEBHOOK="WVVoU01HTklUVFpNZVRsdllqSTVjbU41TlhwaVIwWnFZWGsxYW1JeU1IWmpNbFo1Wkcxc2FscFlUWFpXUkVKQ1RUQlJkMVV4VVRSVE1GbDJVV3BDUWxaVVVUUk5NVVpFVlVWdmRsZEhaelZhUldSdllWZG9SVkV4VmxOVFJrWjZWMnhGZUU1cVVrdFdWbWgyQ2c9PQo="

MAX_RETRIES=3
PUSH_ALL=false

# ─── Parse Arguments ──────────────────────────────────────────────────────────

for arg in "$@"; do
  if [ "$arg" == "--push_all" ]; then
    PUSH_ALL=true
  fi
done

# ─── Decode Webhook 3 Times ───────────────────────────────────────────────────

SLACK_WEBHOOK=$(echo "$ENCODED_WEBHOOK" | base64 --decode | base64 --decode | base64 --decode)

# ─── Slack Alert Function ─────────────────────────────────────────────────────

send_slack_alert() {
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "{
      \"text\": \"❌ *OpenCode Run Failed after $MAX_RETRIES retries!*\",
      \"attachments\": [{
        \"color\": \"danger\",
        \"fields\": [
          {
            \"title\": \"Error\",
            \"value\": \"$1\",
            \"short\": false
          },
          {
            \"title\": \"Time\",
            \"value\": \"$(date)\",
            \"short\": false
          }
        ]
      }]
    }"
}

# ─── Optional: Push All ───────────────────────────────────────────────────────

if [ "$PUSH_ALL" = true ]; then
  echo "📤 --push_all flag detected, running push_to_all.sh..."
  bash push_to_all.sh
  if [ $? -ne 0 ]; then
    echo "⚠️  push_to_all.sh failed, but continuing..."
  else
    echo "✅ push_to_all.sh completed successfully!"
  fi
fi

# ─── Run OpenCode with Retry ──────────────────────────────────────────────────

echo "🚀 Starting opencode run..."

ATTEMPT=0
SUCCESS=false

while [ $ATTEMPT -lt $MAX_RETRIES ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "🔄 Attempt $ATTEMPT of $MAX_RETRIES..."

  opencode run "@prompt.md" --agent bash-automation --model opencode/minimax-m2.5-free
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ opencode run succeeded on attempt $ATTEMPT!"
    SUCCESS=true
    break
  else
    echo "❌ Attempt $ATTEMPT failed with exit code $EXIT_CODE"
    if [ $ATTEMPT -lt $MAX_RETRIES ]; then
      echo "⏳ Retrying in 3 seconds..."
      sleep 3
    fi
  fi
done

# ─── Final Result ─────────────────────────────────────────────────────────────

if [ "$SUCCESS" = false ]; then
  echo "💀 All $MAX_RETRIES attempts failed! Sending Slack alert..."
  send_slack_alert "opencode run @prompt.md failed after $MAX_RETRIES attempts. Last exit code: $EXIT_CODE"
  exit 1
fi