#!/bin/bash
set -e

MASK_ENABLED="$INPUT_MASK_IDENTITIES"
SALT="$INPUT_MASKING_SALT"

if [ "$MASK_ENABLED" = "true" ]; then
  echo "🔒 Identity masking ENABLED (SHA-256 — usernames + repo names)"
  echo "enabled=true" >> $GITHUB_OUTPUT

  # Create masking script
  cat > /tmp/mask_username.sh << 'MASKEOF'
#!/bin/bash
USERNAME="$1"
SALT="$2"
if [ -z "$USERNAME" ]; then
  echo ""
else
  echo -n "${SALT}${USERNAME}" | sha256sum | cut -d' ' -f1 | head -c 16
fi
MASKEOF
  chmod +x /tmp/mask_username.sh
else
  echo "🔓 Identity masking DISABLED (plain text)"
  echo "enabled=false" >> $GITHUB_OUTPUT

  # Create pass-through script
  cat > /tmp/mask_username.sh << 'MASKEOF'
#!/bin/bash
echo "$1"
MASKEOF
  chmod +x /tmp/mask_username.sh
fi

echo "salt=$SALT" >> $GITHUB_OUTPUT
