#!/bin/bash
# Install SSH authorized_keys for root access.

set -euo pipefail

KEYS_FILE="/boot/authorized_keys"

if [ ! -f "$KEYS_FILE" ]; then
    echo "[02-ssh-keys] No authorized_keys found on boot partition, skipping"
    exit 0
fi

mkdir -p /root/.ssh
cp "$KEYS_FILE" /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
chown -R root:root /root/.ssh

# Remove from boot partition after installation
rm -f "$KEYS_FILE"

echo "[02-ssh-keys] SSH authorized_keys installed and removed from boot"
