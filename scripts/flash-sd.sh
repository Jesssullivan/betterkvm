#!/usr/bin/env bash
# flash-sd.sh -- Flash an SD card image with safety checks
# Usage: flash-sd.sh <image-path> <device>
# Works on macOS (diskutil) and Linux (lsblk/dd)
set -euo pipefail

IMAGE_PATH="${1:?Usage: flash-sd.sh <image-path> <device>}"
DEVICE="${2:?Usage: flash-sd.sh <image-path> <device>}"
OS="$(uname)"

# Safety: verify device exists
if [[ "${OS}" == "Darwin" ]]; then
    if ! diskutil info "${DEVICE}" &>/dev/null; then
        echo "ERROR: ${DEVICE} not found. Use 'diskutil list' to find your SD card."
        exit 1
    fi
else
    if [ ! -b "${DEVICE}" ]; then
        echo "ERROR: ${DEVICE} is not a block device"
        exit 1
    fi
fi

# Safety: refuse to write to the boot disk
if [[ "${OS}" == "Darwin" ]]; then
    boot_disk=$(diskutil info / | grep "Part of Whole" | awk '{print $NF}')
    target_disk=$(basename "${DEVICE}" | sed 's/s[0-9]*$//')
    if [[ "${target_disk}" == "${boot_disk}" ]]; then
        echo "ERROR: ${DEVICE} is your boot disk! Refusing to flash."
        exit 1
    fi
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
if [[ "${OS}" == "Darwin" ]]; then
    diskutil list "${DEVICE}"
else
    lsblk "${DEVICE}"
fi
echo ""
echo "This will DESTROY all data on ${DEVICE}."
read -rp "Type 'YES' to proceed: " confirm
[ "${confirm}" = "YES" ] || { echo "Aborted."; exit 1; }

# Unmount all partitions on the device before flashing
if [[ "${OS}" == "Darwin" ]]; then
    echo "Unmounting ${DEVICE}..."
    diskutil unmountDisk "${DEVICE}" 2>/dev/null || true
    raw_device="${DEVICE/disk/rdisk}"
    echo "Flashing to ${raw_device} (raw device for speed)..."
    sudo dd if="${WRITE_IMAGE}" of="${raw_device}" bs=4m status=progress conv=sync
else
    echo "Unmounting partitions on ${DEVICE}..."
    for part in "${DEVICE}"*; do
        umount "${part}" 2>/dev/null || true
    done
    echo "Flashing..."
    sudo dd if="${WRITE_IMAGE}" of="${DEVICE}" bs=4M status=progress conv=fsync oflag=direct
fi
sudo sync
echo ""
echo "Flash complete. Safe to eject ${DEVICE}."
