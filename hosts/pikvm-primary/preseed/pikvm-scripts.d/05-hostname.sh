#!/bin/bash
# Set hostname and trigger reboot to apply all first-boot changes.

set -euo pipefail

HOSTNAME="pikvm-primary"

hostnamectl set-hostname "$HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

# Clean up secrets directory if empty
SECRETS_DIR="/boot/pikvm-secrets"
if [ -d "$SECRETS_DIR" ]; then
    rmdir "$SECRETS_DIR" 2>/dev/null || true
fi

echo "[05-hostname] Hostname set to $HOSTNAME"

# Signal PiKVM to reboot (PiKVM checks for this file)
touch /boot/pikvm-reboot.txt
echo "[05-hostname] Reboot scheduled"
