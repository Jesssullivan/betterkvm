#!/bin/bash
# Set hostname, verify secret cleanup, and trigger reboot.

set -euo pipefail

HOSTNAME="pikvm-primary"

hostnamectl set-hostname "$HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

# Verify all secrets have been cleaned up
SECRETS_DIR="/boot/pikvm-secrets"
if [ -d "$SECRETS_DIR" ]; then
    remaining=$(find "$SECRETS_DIR" -type f 2>/dev/null | wc -l)
    if [ "$remaining" -gt 0 ]; then
        echo "[05-hostname] WARNING: $remaining secret file(s) still on boot partition — force cleaning"
        find "$SECRETS_DIR" -type f -exec sh -c 'dd if=/dev/urandom of="$1" bs=$(stat -c%s "$1" 2>/dev/null || stat -f%z "$1") count=1 conv=notrunc 2>/dev/null; sync; rm -f "$1"' _ {} \;
    fi
    rmdir "$SECRETS_DIR" 2>/dev/null || rm -rf "$SECRETS_DIR"
fi

# Also clean up authorized_keys if 02-ssh-keys.sh missed it
[ -f /boot/authorized_keys ] && rm -f /boot/authorized_keys

echo "[05-hostname] Hostname set to $HOSTNAME, secrets verified clean"

# Signal PiKVM to reboot
touch /boot/pikvm-reboot.txt
echo "[05-hostname] Reboot scheduled"
