#!/bin/bash
set -e

echo "📦 Building payload..."

# Variables
EVENT_TYPE="$DETECTED_EVENT_TYPE"
SENDER=$(/tmp/mask_username.sh "$RAW_SENDER" "$MASKING_SALT")
SOURCE_EVENT_ID="$INPUT_SOURCE_EVENT_ID"
EXTERNAL_REPO_ID="$GITHUB_REPOSITORY_ID"

if [ "$MASKING_ENABLED" = "true" ]; then
  INGESTION_MODE="masked"
  REPO=$(/tmp/mask_username.sh "$GITHUB_REPOSITORY" "$MASKING_SALT")
  REPO_URL=""
  echo "🔒 Masked repo: $GITHUB_REPOSITORY -> $REPO"
else
  INGESTION_MODE="open"
  REPO="$GITHUB_REPOSITORY"
  REPO_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
fi

REPOSITORY_SOURCE=$(printf '%s' "$GITHUB_SERVER_URL" | sed -E 's#^https?://##; s#/.*$##')
if [ -z "$REPOSITORY_SOURCE" ]; then
  REPOSITORY_SOURCE="github.com"
fi

PROVIDER="github"

if [ "$EVENT_TYPE" = "push" ]; then
  PAYLOAD=$(jq -n \
    --arg repo "$REPO" \
    --arg ref "$GITHUB_REF" \
    --arg event_type "push" \
    --arg sender "$SENDER" \
    --arg provider "$PROVIDER" \
    --arg repository_source "$REPOSITORY_SOURCE" \
    --arg external_repo_id "$EXTERNAL_REPO_ID" \
    --arg repo_url "$REPO_URL" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --arg source_event_id "$SOURCE_EVENT_ID" \
    --argjson commits "$COMMITS_JSON" \
    --argjson usernames_masked "$MASKING_ENABLED" \
    --arg ingestion_mode "$INGESTION_MODE" \
    '{
      repository: $repo,
      repository_url: (if $repo_url == "" then null else $repo_url end),
      provider: $provider,
      repository_source: $repository_source,
      external_repo_id: (if $external_repo_id == "" then null else $external_repo_id end),
      ref: $ref,
      default_branch: $default_branch,
      event_type: $event_type,
      sender: $sender,
      usernames_masked: $usernames_masked,
      ingestion_mode: $ingestion_mode,
      commits: $commits,
      source_event_id: (if $source_event_id == "" then null else $source_event_id end)
    }'
  )
else
  PAYLOAD=$(jq -n \
    --arg repo "$REPO" \
    --arg ref "$GITHUB_REF" \
    --arg event_type "pull_request" \
    --arg sender "$SENDER" \
    --arg provider "$PROVIDER" \
    --arg repository_source "$REPOSITORY_SOURCE" \
    --arg external_repo_id "$EXTERNAL_REPO_ID" \
    --arg repo_url "$REPO_URL" \
    --arg default_branch "$DEFAULT_BRANCH" \
    --arg source_event_id "$SOURCE_EVENT_ID" \
    --argjson pull_request "$PR_DATA_JSON" \
    --argjson usernames_masked "$MASKING_ENABLED" \
    --arg ingestion_mode "$INGESTION_MODE" \
    '{
      repository: $repo,
      repository_url: (if $repo_url == "" then null else $repo_url end),
      provider: $provider,
      repository_source: $repository_source,
      external_repo_id: (if $external_repo_id == "" then null else $external_repo_id end),
      ref: $ref,
      default_branch: $default_branch,
      event_type: $event_type,
      sender: $sender,
      usernames_masked: $usernames_masked,
      ingestion_mode: $ingestion_mode,
      pull_request: $pull_request,
      source_event_id: (if $source_event_id == "" then null else $source_event_id end)
    }'
  )
fi

# Save payload to file (to avoid shell escaping issues)
echo "$PAYLOAD" > /tmp/devxp_payload.json

echo "✅ Payload built successfully"
echo "📋 Payload preview:"
echo "$PAYLOAD" | jq -c '.' | head -c 500
echo ""
