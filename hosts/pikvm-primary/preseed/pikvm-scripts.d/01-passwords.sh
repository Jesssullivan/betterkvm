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

# Set root password hash
if [ -f "$SECRETS_DIR/root-password-hash" ]; then
    hash=$(cat "$SECRETS_DIR/root-password-hash")
    usermod -p "$hash" root
    rm -f "$SECRETS_DIR/root-password-hash"
    echo "[01-passwords] Root password set"
fi

# Set kvmd admin password
if [ -f "$SECRETS_DIR/kvmd-admin-password" ]; then
    password=$(cat "$SECRETS_DIR/kvmd-admin-password")
    kvmd-htpasswd set admin "$password"
    rm -f "$SECRETS_DIR/kvmd-admin-password"
    echo "[01-passwords] kvmd admin password set"
fi
