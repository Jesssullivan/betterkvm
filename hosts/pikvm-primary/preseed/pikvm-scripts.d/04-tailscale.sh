#!/bin/bash
# Install and authenticate Tailscale on PiKVM.
# Auth key is preseeded to boot partition and deleted after use.

set -euo pipefail

SECRETS_DIR="/boot/pikvm-secrets"
AUTHKEY_FILE="$SECRETS_DIR/tailscale-authkey"

if [ ! -f "$AUTHKEY_FILE" ]; then
    echo "[04-tailscale] No Tailscale auth key found, skipping"
    exit 0
fi

authkey=$(cat "$AUTHKEY_FILE")

# Install tailscale-pikvm if not already present
if ! command -v tailscale &>/dev/null; then
    echo "[04-tailscale] Installing tailscale-pikvm..."
    pacman -Sy --noconfirm tailscale-pikvm || {
        echo "[04-tailscale] ERROR: Failed to install tailscale-pikvm"
        exit 1
    }
fi

systemctl enable --now tailscaled

# Authenticate with the preseeded auth key
tailscale up --authkey="$authkey" --hostname=pikvm-primary

# Clean up the auth key
rm -f "$AUTHKEY_FILE"

echo "[04-tailscale] Tailscale authenticated as pikvm-primary"
