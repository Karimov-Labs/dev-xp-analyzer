#!/bin/bash
set -e

echo "📥 Collecting pull request event data..."

# Variables passed from env
REPO_FULL_NAME="$GITHUB_REPOSITORY"

# Apply masking if enabled
SALT="$MASKING_SALT"
PR_AUTHOR=$(bash /tmp/mask_username.sh "$RAW_PR_AUTHOR" "$SALT")

if [ "$MASKING_ENABLED" = "true" ]; then
  echo "🔒 Masked PR author: $RAW_PR_AUTHOR -> $PR_AUTHOR"
fi

echo "📊 Analyzing PR #$PR_NUMBER: $PR_TITLE"

# Fetch PR files using GitHub API
PR_FILES=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$REPO_FULL_NAME/pulls/$PR_NUMBER/files?per_page=$INPUT_MAX_FILES" \
  | jq -c '[.[] | {
    filename: .filename,
    status: .status,
    additions: .additions,
    deletions: .deletions,
    changes: .changes,
    previous_filename: .previous_filename
  }]'
)

# Fetch PR commits and apply masking if enabled
RAW_PR_COMMITS=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$REPO_FULL_NAME/pulls/$PR_NUMBER/commits" \
  | jq -c '[.[] | {
    sha: .sha,
    author: (.author.login // ""),
    author_email: .commit.author.email,
    vcs_username: (.author.login // null),
    message: .commit.message,
    timestamp: .commit.author.date
  }]'
)

MISSING_PR_AUTHOR_COUNT=$(echo "$RAW_PR_COMMITS" | jq '[.[] | select(.author == "")] | length')
if [ "$MISSING_PR_AUTHOR_COUNT" -gt 0 ]; then
  echo "❌ Failed to resolve GitHub usernames for $MISSING_PR_AUTHOR_COUNT PR commit(s)"
  echo "💡 Dev XP requires GitHub usernames for commit attribution and Backstage unmasking"
  echo "$RAW_PR_COMMITS" | jq -r '.[] | select(.author == "") | "- missing login for commit \(.sha)"'
  exit 1
fi

# Apply masking to commit authors if enabled
if [ "$MASKING_ENABLED" = "true" ]; then
  # Process each commit to hash authors and github usernames
  MASKED_COMMITS="[]"
  for row in $(echo "$RAW_PR_COMMITS" | jq -r '.[] | @base64'); do
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }
    SHA=$(_jq '.sha')
    RAW_COMMIT_AUTHOR=$(_jq '.author')
    RAW_COMMIT_EMAIL=$(_jq '.author_email')
    RAW_GH_USERNAME=$(_jq '.vcs_username // empty')
    MSG=$(_jq '.message')
    TS=$(_jq '.timestamp')

    MASKED_AUTHOR=""
    if [ -n "$RAW_COMMIT_AUTHOR" ]; then
      MASKED_AUTHOR=$(bash /tmp/mask_username.sh "$RAW_COMMIT_AUTHOR" "$SALT")
    fi
    MASKED_EMAIL=$(bash /tmp/mask_username.sh "$RAW_COMMIT_EMAIL" "$SALT")
    MASKED_GH_USERNAME=""
    if [ -n "$RAW_GH_USERNAME" ]; then
      MASKED_GH_USERNAME=$(bash /tmp/mask_username.sh "$RAW_GH_USERNAME" "$SALT")
    fi

    MASKED_COMMITS=$(echo "$MASKED_COMMITS" | jq -c \
      --arg sha "$SHA" \
      --arg author "$MASKED_AUTHOR" \
      --arg email "$MASKED_EMAIL" \
      --arg gh_user "$MASKED_GH_USERNAME" \
      --arg msg "$MSG" \
      --arg ts "$TS" \
      '. + [{sha: $sha, author: (if $author == "" then null else $author end), author_email: $email, vcs_username: (if $gh_user == "" then null else $gh_user end), message: $msg, timestamp: $ts}]')
  done
  PR_COMMITS="$MASKED_COMMITS"
  echo "🔒 Masked $(echo "$RAW_PR_COMMITS" | jq 'length') commit authors"
else
  PR_COMMITS="$RAW_PR_COMMITS"
fi

# Build output with PR info
PR_JSON=$(jq -n \
  --arg number "$PR_NUMBER" \
  --arg title "$PR_TITLE" \
  --arg author "$PR_AUTHOR" \
  --arg merged_at "$PR_MERGED_AT" \
  --arg base_sha "$PR_BASE" \
  --arg head_sha "$PR_HEAD" \
  --argjson files "$PR_FILES" \
  --argjson commits "$PR_COMMITS" \
  '{
    number: ($number | tonumber),
    title: $title,
    author: $author,
    merged_at: $merged_at,
    base_sha: $base_sha,
    head_sha: $head_sha,
    files: $files,
    commits: $commits
  }'
)

echo "pr_json<<EOF" >> $GITHUB_OUTPUT
echo "$PR_JSON" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "✅ Collected data for $(echo "$PR_FILES" | jq 'length') files across $(echo "$PR_COMMITS" | jq 'length') commits"
