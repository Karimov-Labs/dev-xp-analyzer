#!/bin/bash
set -e

EVENT_TYPE="$INPUT_EVENT_TYPE"
PR_NUMBER_RAW="${PR_NUMBER:-}"

if [ "$EVENT_TYPE" = "auto" ]; then
  if [ "$GITHUB_EVENT_NAME" = "pull_request" ]; then
    EVENT_TYPE="pull_request"
  elif [ "$GITHUB_EVENT_NAME" = "push" ]; then
    EVENT_TYPE="push"
  else
    echo "⚠️ Unsupported GitHub event: $GITHUB_EVENT_NAME, defaulting to push"
    EVENT_TYPE="push"
  fi
fi

if [ "$EVENT_TYPE" = "pull_request" ] && [ -z "$PR_NUMBER_RAW" ]; then
  echo "⚠️ pull_request event type requested but no PR context found. Falling back to push analysis."
  EVENT_TYPE="push"
fi

# Validate final event type
if [ "$EVENT_TYPE" != "push" ] && [ "$EVENT_TYPE" != "pull_request" ]; then
  echo "❌ Error: Invalid event-type '$EVENT_TYPE'. Supported values are: auto, push, pull_request"
  exit 1
fi

echo "event_type=$EVENT_TYPE" >> $GITHUB_OUTPUT
echo "📌 Detected event type: $EVENT_TYPE"
