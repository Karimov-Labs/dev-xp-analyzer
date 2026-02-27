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
  BEFORE_SHA=""
fi

# Ensure BEFORE_SHA is reachable in the local clone (handles shallow checkouts)
USE_SHOW_FALLBACK=false
if [ -n "$BEFORE_SHA" ]; then
  if ! git cat-file -e "$BEFORE_SHA" 2>/dev/null; then
    echo "⚠️  Before SHA $BEFORE_SHA not in shallow clone, fetching..."
    git fetch --depth=1 origin "$BEFORE_SHA" 2>/dev/null || true
  fi
  if ! git cat-file -e "$BEFORE_SHA" 2>/dev/null; then
    echo "⚠️  Could not resolve before SHA, falling back to single-commit diff"
    USE_SHOW_FALLBACK=true
  fi
else
  USE_SHOW_FALLBACK=true
fi

if [ "$USE_SHOW_FALLBACK" = "true" ]; then
  echo "📊 Analyzing single commit $COMMIT_SHA"
else
  echo "📊 Analyzing commits from $BEFORE_SHA to $COMMIT_SHA"
fi

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
# Use git show for single-commit diff (works with shallow clones), git diff for range
if [ "$USE_SHOW_FALLBACK" = "true" ]; then
  FILES_RAW=$(git show --name-status --diff-filter=ACDMR --format='' "$COMMIT_SHA" 2>/dev/null || echo "")
  STATS_RAW=$(git show --numstat --format='' "$COMMIT_SHA" 2>/dev/null || echo "")
else
  FILES_RAW=$(git diff --name-status "$BEFORE_SHA" "$COMMIT_SHA" 2>/dev/null || echo "")
  STATS_RAW=$(git diff --numstat "$BEFORE_SHA" "$COMMIT_SHA" 2>/dev/null || echo "")
fi

FILES_JSON=$(echo "$FILES_RAW" | head -n $INPUT_MAX_FILES | jq -R -s -c '
  split("\n") |
  map(select(length > 0)) |
  map(split("\t") | {
    status: (if .[0] == "A" then "added" elif .[0] == "D" then "deleted" elif .[0] == "M" then "modified" elif .[0][0:1] == "R" then "renamed" else "modified" end),
    filename: (if (.[0][0:1] == "R") then .[2] else .[1] end),
    previous_filename: (if (.[0][0:1] == "R") then .[1] else null end)
  })
')

# Get file stats (additions/deletions)
STATS_JSON=$(echo "$STATS_RAW" | head -n $INPUT_MAX_FILES | jq -R -s -c '
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
