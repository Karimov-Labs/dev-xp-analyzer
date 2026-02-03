#!/bin/bash
set -e

echo "🚀 Submitting analysis data to Dev XP..."

# API_ENDPOINT, API_TOKEN from env

# Submit the payload
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${API_ENDPOINT}/api/github-action/analyze" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -d @/tmp/devxp_payload.json)

# Parse response
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "📡 Response code: $HTTP_CODE"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "status=success" >> $GITHUB_OUTPUT
  WORKFLOW_ID=$(echo "$BODY" | jq -r '.workflowId // .workflow_id // "unknown"')
  MESSAGE=$(echo "$BODY" | jq -r '.message // "Analysis submitted successfully"')
  echo "workflow_id=$WORKFLOW_ID" >> $GITHUB_OUTPUT
  echo "message=$MESSAGE" >> $GITHUB_OUTPUT
  echo "✅ Analysis submitted successfully!"
  echo "📋 Workflow ID: $WORKFLOW_ID"
else
  echo "status=failed" >> $GITHUB_OUTPUT
  echo "workflow_id=" >> $GITHUB_OUTPUT
  ERROR_MSG=$(echo "$BODY" | jq -r '.error // .message // "Unknown error"')
  echo "message=$ERROR_MSG" >> $GITHUB_OUTPUT
  echo "❌ Failed to submit analysis: $ERROR_MSG"
  echo "Response body: $BODY"
  exit 1
fi

# Cleanup
rm -f /tmp/devxp_payload.json
