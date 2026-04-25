#!/bin/bash
# Install and authenticate Tailscale on PiKVM.
# Auth key is preseeded to boot partition and deleted after use.

set -euo pipefail

SECRETS_DIR="/boot/pikvm-secrets"
AUTHKEY_FILE="$SECRETS_DIR/tailscale-authkey"

if [ ! -d "$SECRETS_DIR" ]; then
    echo "[04-tailscale] No secrets directory found, skipping"
    exit 0
fi

if [ ! -f "$AUTHKEY_FILE" ]; then
    echo "[04-tailscale] No Tailscale auth key found, skipping"
    exit 0
fi

secure_delete() {
    local f="$1"
    if [ -f "$f" ]; then
        local sz
        sz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
        dd if=/dev/urandom of="$f" bs="$sz" count=1 conv=notrunc 2>/dev/null || true
        sync
        rm -f "$f"
    fi
}

# Always securely delete the auth key, even if tailscale up fails
trap 'secure_delete "$AUTHKEY_FILE"' EXIT

# Install tailscale if not already present
if ! command -v tailscale &>/dev/null; then
    echo "[04-tailscale] Installing tailscale..."
    pacman -Sy --noconfirm tailscale || {
        echo "[04-tailscale] WARN: 'tailscale' not found, trying tailscale-pikvm..."
        pacman -Sy --noconfirm tailscale-pikvm || {
            echo "[04-tailscale] ERROR: Failed to install tailscale"
            exit 1
        }
    }
fi

systemctl enable --now tailscaled

# Authenticate via file descriptor to avoid exposing authkey in process table
tailscale up --authkey="file:$AUTHKEY_FILE" --hostname=pikvm-primary || {
    echo "[04-tailscale] Retrying after 5s..."
    sleep 5
    tailscale up --authkey="file:$AUTHKEY_FILE" --hostname=pikvm-primary
}

echo "[04-tailscale] Tailscale authenticated as pikvm-primary"
