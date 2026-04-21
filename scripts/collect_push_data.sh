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
RAW_AUTHOR_EMAIL=$(git log -1 --format='%ae' $COMMIT_SHA)
COMMIT_MESSAGE=$(git log -1 --format='%s' $COMMIT_SHA)
COMMIT_DATE=$(git log -1 --format='%aI' $COMMIT_SHA)
RAW_AUTHOR=""
SALT="$MASKING_SALT"

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

# Resolve VCS username from commit SHA via provider API
# This gives us the actual provider login (e.g. "kerimovscreations") linked to the
# commit email, which is more reliable than github.actor (the workflow trigger).
RAW_VCS_USERNAME=""
if [ -n "$COMMIT_SHA" ] && [ -n "$GITHUB_REPOSITORY" ]; then
  echo "🔍 Resolving VCS username for commit $COMMIT_SHA..."

  set +e
  COMMIT_LOOKUP_JSON=$(gh api "/repos/$GITHUB_REPOSITORY/commits/$COMMIT_SHA" 2>&1)
  COMMIT_LOOKUP_EXIT=$?
  set -e

  if [ $COMMIT_LOOKUP_EXIT -eq 0 ]; then
    RAW_VCS_USERNAME=$(printf '%s' "$COMMIT_LOOKUP_JSON" | jq -r '.author.login // empty')
    if [ -n "$RAW_VCS_USERNAME" ]; then
      RAW_AUTHOR="$RAW_VCS_USERNAME"
      echo "✅ Resolved VCS username: $RAW_VCS_USERNAME"
    else
      echo "❌ Could not resolve VCS username from commit because GitHub returned null author.login"
      echo "💡 This usually means the commit author is not linked to a GitHub account for this commit"
      echo "💡 Dev XP requires GitHub usernames for commit attribution and Backstage unmasking"
      exit 1
    fi
  else
    echo "❌ Failed to resolve VCS username from GitHub API (gh api exited with code $COMMIT_LOOKUP_EXIT)"
    echo "💡 This can be caused by network/proxy/DNS/TLS issues on enterprise runners, GitHub API auth problems, rate limits, or host misconfiguration"
    echo "gh api error: $(printf '%s' "$COMMIT_LOOKUP_JSON" | tr '\n' ' ' | cut -c 1-400)"
    exit 1
  fi
else
  echo "❌ Cannot resolve VCS username because COMMIT_SHA or GITHUB_REPOSITORY is missing"
  exit 1
fi

# Apply username masking after author resolution so author only carries the GitHub login when available.
AUTHOR=""
if [ -n "$RAW_AUTHOR" ]; then
  AUTHOR=$(bash /tmp/mask_username.sh "$RAW_AUTHOR" "$SALT")
fi
AUTHOR_EMAIL=$(bash /tmp/mask_username.sh "$RAW_AUTHOR_EMAIL" "$SALT")

if [ "$MASKING_ENABLED" = "true" ] && [ -n "$RAW_AUTHOR" ]; then
  echo "🔒 Masked author: $RAW_AUTHOR -> $AUTHOR"
fi

# Apply masking to VCS username if enabled
VCS_USERNAME=""
if [ -n "$RAW_VCS_USERNAME" ]; then
  VCS_USERNAME=$(bash /tmp/mask_username.sh "$RAW_VCS_USERNAME" "$SALT")
fi

# Build commits array (single commit for push)
COMMITS_JSON=$(jq -n \
  --arg sha "$COMMIT_SHA" \
  --arg author "$AUTHOR" \
  --arg email "$AUTHOR_EMAIL" \
  --arg vcs_username "$VCS_USERNAME" \
  --arg message "$COMMIT_MESSAGE" \
  --arg date "$COMMIT_DATE" \
  --argjson files "$MERGED_FILES" \
  '[{
    sha: $sha,
    author: (if $author == "" then null else $author end),
    author_email: $email,
    vcs_username: (if $vcs_username == "" then null else $vcs_username end),
    message: $message,
    timestamp: $date,
    files: $files
  }]'
)

echo "commits_json<<EOF" >> $GITHUB_OUTPUT
echo "$COMMITS_JSON" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

echo "✅ Collected data for $(echo "$MERGED_FILES" | jq 'length') files"
