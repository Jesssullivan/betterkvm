#!/usr/bin/env bash
# serial-discover.sh -- Discover USB serial devices (local or remote)
# Outputs device paths, vendor/model info, and serial numbers for udev rules
set -euo pipefail

# Run locally or on the serial-console Pi
if [ "${1:-}" = "--remote" ]; then
    HOST="${2:-serial-console}"
    echo "Discovering serial devices on ${HOST}..."
    ssh "root@${HOST}" 'bash -s' < "$0"
    exit $?
fi

echo "=== USB Serial Devices ==="
echo ""

found=0
for dev in /dev/ttyUSB* /dev/ttyACM*; do
    [ -e "$dev" ] || continue
    found=1

    echo "Device: $dev"
    # Get key udev properties
    props=$(udevadm info --query=property --name="$dev" 2>/dev/null || true)

    vendor=$(echo "$props" | grep "^ID_VENDOR=" | cut -d= -f2)
    model=$(echo "$props" | grep "^ID_MODEL=" | cut -d= -f2)
    serial=$(echo "$props" | grep "^ID_SERIAL_SHORT=" | cut -d= -f2)
    vid=$(echo "$props" | grep "^ID_VENDOR_ID=" | cut -d= -f2)
    pid=$(echo "$props" | grep "^ID_MODEL_ID=" | cut -d= -f2)
    devpath=$(udevadm info -a -n "$dev" 2>/dev/null | grep "ATTRS{devpath}" | head -1 | grep -oP '=="[^"]*"' | tr -d '="')

    printf "  Vendor:     %s (%s)\n" "${vendor:-unknown}" "${vid:-????}"
    printf "  Model:      %s (%s)\n" "${model:-unknown}" "${pid:-????}"
    printf "  Serial:     %s\n" "${serial:-NONE (use port path for udev)}"
    printf "  USB Path:   %s\n" "${devpath:-unknown}"

    # Suggest udev rule
    if [ -n "$serial" ]; then
        echo "  udev rule:  SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"${vid}\", ATTRS{serial}==\"${serial}\", SYMLINK+=\"serial/CHANGEME\""
    elif [ -n "$devpath" ]; then
        echo "  udev rule:  SUBSYSTEM==\"tty\", ATTRS{devpath}==\"${devpath}\", SYMLINK+=\"serial/CHANGEME\""
    fi
    echo ""
done

if [ "$found" -eq 0 ]; then
    echo "  No USB serial devices found."
    echo "  Check USB connections and adapter drivers."
fi

# Also show any existing symlinks
if find /dev/serial/by-id/ -maxdepth 1 -type l 2>/dev/null | head -1 | grep -q .; then
    echo "=== Persistent Paths (by-id) ==="
    ls -la /dev/serial/by-id/ 2>/dev/null
fi
