#!/bin/bash

# Webhook encoded 3 times with base64
ENCODED_WEBHOOK="WVVoU01HTklUVFpNZVRsdllqSTVjbU41TlhwaVIwWnFZWGsxYW1JeU1IWmpNbFo1Wkcxc2FscFlUWFpXUkVKQ1RUQlJkMVV4VVRSVE1GbDJVV3BDUWxaVVVUUk5NVVpFVlVWdmRsZEhaelZhUldSdllWZG9SVkV4VmxOVFJrWjZWMnhGZUU1cVVrdFdWbWgyQ2c9PQo="

# Decode 3 times to get original URL
SLACK_WEBHOOK=$(echo "$ENCODED_WEBHOOK" | base64 --decode | base64 --decode | base64 --decode)

send_slack_alert() {
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "{
      \"text\": \"❌ *VPS Sync Failed!*\",
      \"attachments\": [{
        \"color\": \"danger\",
        \"fields\": [{
          \"title\": \"Error\",
          \"value\": \"$1\",
          \"short\": false
        },
        {
          \"title\": \"Time\",
          \"value\": \"$(date)\",
          \"short\": false
        }]
      }]
    }"
}

echo "🚀 Starting sync..."

rsync -avz \
  /Users/solaman/ai-project/github_s_d_t_a/ \
  root@axovps.firedns.xyz:/root/ai-project/

if [ $? -ne 0 ]; then
  echo "❌ Sync failed! Sending Slack alert..."
  send_slack_alert "rsync failed while syncing to root@axovps.firedns.xyz:/root/ai-project/"
  exit 1
fi

echo "✅ Sync complete!"