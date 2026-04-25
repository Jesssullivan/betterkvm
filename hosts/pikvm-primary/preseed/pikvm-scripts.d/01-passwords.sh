#!/bin/bash
# Set root password and kvmd admin password from preseeded secrets.
# Secrets are placed on the boot partition by `just preseed-pikvm`
# and deleted after use.

set -euo pipefail

SECRETS_DIR="/boot/pikvm-secrets"

if [ ! -d "$SECRETS_DIR" ]; then
    echo "[01-passwords] No secrets directory found, skipping"
    exit 0
fi

secure_delete() {
    local f="$1"
    if [ -f "$f" ]; then
        # Overwrite before unlinking — FAT32 flash media best-effort wipe
        dd if=/dev/urandom of="$f" bs=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") count=1 conv=notrunc 2>/dev/null || true
        sync
        rm -f "$f"
    fi
}

# Ensure secrets are cleaned up even on failure
trap 'secure_delete "$SECRETS_DIR/root-password-hash"; secure_delete "$SECRETS_DIR/kvmd-admin-password"' EXIT

# Set root password hash
if [ -f "$SECRETS_DIR/root-password-hash" ]; then
    hash=$(cat "$SECRETS_DIR/root-password-hash")
    usermod -p "$hash" root
    secure_delete "$SECRETS_DIR/root-password-hash"
    unset hash
    echo "[01-passwords] Root password set"
fi

# Set kvmd admin password
if [ -f "$SECRETS_DIR/kvmd-admin-password" ]; then
    kvmd-htpasswd set admin "$(cat "$SECRETS_DIR/kvmd-admin-password")"
    secure_delete "$SECRETS_DIR/kvmd-admin-password"
    echo "[01-passwords] kvmd admin password set"
fi

trap - EXIT
