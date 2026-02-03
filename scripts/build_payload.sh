#!/bin/bash
set -e

echo "📦 Building payload..."

# Variables
EVENT_TYPE="$DETECTED_EVENT_TYPE"
SENDER=$(/tmp/mask_username.sh "$RAW_SENDER" "$MASKING_SALT")

if [ "$EVENT_TYPE" = "push" ]; then
  PAYLOAD=$(jq -n \
    --arg repo "$GITHUB_REPOSITORY" \
    --arg ref "$GITHUB_REF" \
    --arg event_type "push" \
    --arg sender "$SENDER" \
    --arg repo_url "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --argjson commits "$COMMITS_JSON" \
    --argjson usernames_masked "$MASKING_ENABLED" \
    '{
      repository: $repo,
      repository_url: $repo_url,
      ref: $ref,
      default_branch: $default_branch,
      event_type: $event_type,
      sender: $sender,
      usernames_masked: $usernames_masked,
      commits: $commits
    }'
  )
else
  PAYLOAD=$(jq -n \
    --arg repo "$GITHUB_REPOSITORY" \
    --arg ref "$GITHUB_REF" \
    --arg event_type "pull_request" \
    --arg sender "$SENDER" \
    --arg repo_url "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --argjson pull_request "$PR_DATA_JSON" \
    --argjson usernames_masked "$MASKING_ENABLED" \
    '{
      repository: $repo,
      repository_url: $repo_url,
      ref: $ref,
      default_branch: $default_branch,
      event_type: $event_type,
      sender: $sender,
      usernames_masked: $usernames_masked,
      pull_request: $pull_request
    }'
  )
fi

# Save payload to file (to avoid shell escaping issues)
echo "$PAYLOAD" > /tmp/devxp_payload.json

echo "✅ Payload built successfully"
echo "📋 Payload preview:"
echo "$PAYLOAD" | jq -c '.' | head -c 500
echo ""
