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

authkey=$(cat "$AUTHKEY_FILE")

# Always delete the auth key, even if tailscale up fails
cleanup() { rm -f "$AUTHKEY_FILE"; }
trap cleanup EXIT

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

# Authenticate — retry once after a short delay if tailscaled is still starting
tailscale up --authkey="$authkey" --hostname=pikvm-primary || {
    echo "[04-tailscale] Retrying after 5s..."
    sleep 5
    tailscale up --authkey="$authkey" --hostname=pikvm-primary
}

echo "[04-tailscale] Tailscale authenticated as pikvm-primary"
