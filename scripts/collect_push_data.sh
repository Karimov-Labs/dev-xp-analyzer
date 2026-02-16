#!/bin/bash
set -e

echo "📥 Collecting push event data..."

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Git repository not found in workspace. Add 'actions/checkout@v4' before using Karimov-Labs/dev-xp-analyzer."
  exit 1
fi

# Get commit details
COMMIT_SHA="$GITHUB_SHA"
BEFORE_SHA="$GITHUB_EVENT_BEFORE"

# Handle first push (no before SHA)
if [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ]; then
  BEFORE_SHA=$(git rev-parse HEAD~1 2>/dev/null || echo "$COMMIT_SHA")
fi

echo "📊 Analyzing commits from $BEFORE_SHA to $COMMIT_SHA"

# Collect commit info
RAW_AUTHOR=$(git log -1 --format='%an' $COMMIT_SHA)
RAW_AUTHOR_EMAIL=$(git log -1 --format='%ae' $COMMIT_SHA)
COMMIT_MESSAGE=$(git log -1 --format='%s' $COMMIT_SHA)
COMMIT_DATE=$(git log -1 --format='%aI' $COMMIT_SHA)

# Apply username masking if enabled
SALT="$MASKING_SALT"
AUTHOR=$(/tmp/mask_username.sh "$RAW_AUTHOR" "$SALT")
AUTHOR_EMAIL=$(/tmp/mask_username.sh "$RAW_AUTHOR_EMAIL" "$SALT")

if [ "$MASKING_ENABLED" = "true" ]; then
  echo "🔒 Masked author: $RAW_AUTHOR -> $AUTHOR"
fi

# Get changed files with stats
FILES_JSON=$(git diff --name-status $BEFORE_SHA $COMMIT_SHA 2>/dev/null | head -n $INPUT_MAX_FILES | jq -R -s -c '
  split("\n") |
  map(select(length > 0)) |
  map(split("\t") | {
    status: (if .[0] == "A" then "added" elif .[0] == "D" then "deleted" elif .[0] == "M" then "modified" elif .[0][0:1] == "R" then "renamed" else "modified" end),
    filename: (if (.[0][0:1] == "R") then .[2] else .[1] end),
    previous_filename: (if (.[0][0:1] == "R") then .[1] else null end)
  })
')

# Get file stats (additions/deletions)
STATS_JSON=$(git diff --numstat $BEFORE_SHA $COMMIT_SHA 2>/dev/null | head -n $INPUT_MAX_FILES | jq -R -s -c '
  split("\n") |
  map(select(length > 0)) |
  map(split("\t") | {
    filename: .[2],
    additions: (.[0] | if . == "-" then 0 else tonumber end),
    deletions: (.[1] | if . == "-" then 0 else tonumber end)
  }) |
  INDEX(.filename)
')

# Merge file info with stats
MERGED_FILES=$(echo "$FILES_JSON" | jq -c --argjson stats "$STATS_JSON" '
  map(. + ($stats[.filename] // {additions: 0, deletions: 0}))
')

# Build commits array (single commit for push)
COMMITS_JSON=$(jq -n \
  --arg sha "$COMMIT_SHA" \
  --arg author "$AUTHOR" \
  --arg email "$AUTHOR_EMAIL" \
  --arg message "$COMMIT_MESSAGE" \
  --arg date "$COMMIT_DATE" \
  --argjson files "$MERGED_FILES" \
  '[{
    sha: $sha,
    author: $author,
    author_email: $email,
    message: $message,
    timestamp: $date,
    files: $files
  }]'
)

echo "commits_json<<EOF" >> $GITHUB_OUTPUT
echo "$COMMITS_JSON" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "✅ Collected data for $(echo "$MERGED_FILES" | jq 'length') files"
