#!/bin/bash
# Install kvmd override.yaml from boot partition.

set -euo pipefail

OVERRIDE_SRC="/boot/override.yaml"
OVERRIDE_DST="/etc/kvmd/override.yaml"

if [ ! -f "$OVERRIDE_SRC" ]; then
    echo "[03-override] No override.yaml found on boot partition, skipping"
    exit 0
fi

cp "$OVERRIDE_SRC" "$OVERRIDE_DST"
chown kvmd:kvmd "$OVERRIDE_DST"
chmod 644 "$OVERRIDE_DST"

echo "[03-override] override.yaml installed to $OVERRIDE_DST"
