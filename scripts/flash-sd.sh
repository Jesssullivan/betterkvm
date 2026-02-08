#!/usr/bin/env bash
# flash-sd.sh -- Flash an SD card image with safety checks
# Usage: flash-sd.sh <image-path> <device>
set -euo pipefail

IMAGE_PATH="${1:?Usage: flash-sd.sh <image-path> <device>}"
DEVICE="${2:?Usage: flash-sd.sh <image-path> <device>}"

# Safety: must be a block device
if [ ! -b "${DEVICE}" ]; then
    echo "ERROR: ${DEVICE} is not a block device"
    exit 1
fi

# Safety: refuse to write to mounted devices
if mount | grep -q "^${DEVICE}"; then
    echo "ERROR: ${DEVICE} has mounted partitions!"
    mount | grep "^${DEVICE}"
    exit 1
fi

# Decompress if needed
WRITE_IMAGE="${IMAGE_PATH}"
if [[ "${IMAGE_PATH}" == *.zst ]]; then
    WRITE_IMAGE="${IMAGE_PATH%.zst}"
    if [ ! -f "${WRITE_IMAGE}" ]; then
        echo "Decompressing (zstd)..."
        zstd -d "${IMAGE_PATH}" -o "${WRITE_IMAGE}"
    fi
elif [[ "${IMAGE_PATH}" == *.xz ]]; then
    WRITE_IMAGE="${IMAGE_PATH%.xz}"
    if [ ! -f "${WRITE_IMAGE}" ]; then
        echo "Decompressing (xz)..."
        xz -dk "${IMAGE_PATH}"
    fi
fi

echo "=== Flash Summary ==="
echo "Image:  ${WRITE_IMAGE} ($(du -h "${WRITE_IMAGE}" | cut -f1))"
echo "Device: ${DEVICE}"
lsblk "${DEVICE}"
echo ""
echo "This will DESTROY all data on ${DEVICE}."
read -rp "Type 'YES' to proceed: " confirm
[ "${confirm}" = "YES" ] || { echo "Aborted."; exit 1; }

echo "Flashing..."
sudo dd if="${WRITE_IMAGE}" of="${DEVICE}" bs=4M status=progress conv=fsync oflag=direct
sudo sync
echo ""
echo "Flash complete. Safe to eject ${DEVICE}."
