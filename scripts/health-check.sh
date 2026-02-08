#!/usr/bin/env bash
# health-check.sh -- Comprehensive KVM lab health check
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0; FAIL=0; WARN=0

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ${GREEN}PASS${NC}  %s\n" "${name}"
        ((PASS++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "${name}"
        ((FAIL++))
    fi
}

check_warn() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "  ${GREEN}PASS${NC}  %s\n" "${name}"
        ((PASS++))
    else
        printf "  ${YELLOW}WARN${NC}  %s\n" "${name}"
        ((WARN++))
    fi
}

echo "=== KVM Lab Health Check ==="
echo "$(date)"
echo ""

# -- Pi Connectivity --
echo "-- Pi Connectivity --"
PIKVM_ADDR="${PIKVM_HOST:-pikvm-primary}"
SERIAL_ADDR="${SERIAL_HOST:-serial-console}"

check "pikvm-primary SSH" ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${PIKVM_ADDR}" true
check "serial-console SSH" ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${SERIAL_ADDR}" true
echo ""

# -- Tailscale --
echo "-- Tailscale Network --"
check "Local Tailscale daemon" tailscale status
check_warn "pikvm-primary on Tailscale" tailscale ping --timeout=3s "${PIKVM_ADDR}"
check_warn "serial-console on Tailscale" tailscale ping --timeout=3s "${SERIAL_ADDR}"
echo ""

# -- TESmart Switch --
echo "-- TESmart KVM Switch --"
TESMART_HOST="${TESMART_HOST:-192.168.1.10}"
check "TESmart TCP:5000 reachable" \
    bash -c "timeout 3 bash -c '</dev/tcp/${TESMART_HOST}/5000'"
check "TESmart port query" \
    python3 "$(dirname "$0")/../packages/tesmart-ctl/tesmart_ctl.py" --host "${TESMART_HOST}" get
echo ""

# -- PiKVM Services --
echo "-- PiKVM (Pi #1) --"
check "kvmd service" ssh -o ConnectTimeout=3 "root@${PIKVM_ADDR}" systemctl is-active kvmd
check_warn "ustreamer service" ssh -o ConnectTimeout=3 "root@${PIKVM_ADDR}" systemctl is-active kvmd-streamer
echo ""

# -- Serial Console Services --
echo "-- Serial Console (Pi #2) --"
check "ser2net service" ssh -o ConnectTimeout=3 "root@${SERIAL_ADDR}" systemctl is-active ser2net
check_warn "NUT upsd service" ssh -o ConnectTimeout=3 "root@${SERIAL_ADDR}" systemctl is-active nut-server
echo ""

# -- CPU Temperatures --
echo "-- CPU Temperatures --"
for label_addr in "pikvm-primary:${PIKVM_ADDR}" "serial-console:${SERIAL_ADDR}"; do
    label="${label_addr%%:*}"
    addr="${label_addr##*:}"
    temp=$(ssh -o ConnectTimeout=3 "root@${addr}" \
        'echo $(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))' 2>/dev/null || echo "?")
    if [ "${temp}" != "?" ] && [ "${temp}" -lt 70 ]; then
        printf "  ${GREEN}%3s C${NC}  %s\n" "${temp}" "${label}"
    elif [ "${temp}" != "?" ] && [ "${temp}" -lt 80 ]; then
        printf "  ${YELLOW}%3s C${NC}  %s (warm)\n" "${temp}" "${label}"
    elif [ "${temp}" != "?" ]; then
        printf "  ${RED}%3s C${NC}  %s (HOT)\n" "${temp}" "${label}"
    else
        printf "  ${RED}  ? C${NC}  %s (unreachable)\n" "${label}"
    fi
done
echo ""

# -- UPS Status --
echo "-- UPS Status --"
ups_status=$(ssh -o ConnectTimeout=3 "root@${SERIAL_ADDR}" 'upsc rack-ups ups.status 2>/dev/null' || echo "UNKNOWN")
ups_charge=$(ssh -o ConnectTimeout=3 "root@${SERIAL_ADDR}" 'upsc rack-ups battery.charge 2>/dev/null' || echo "?")
echo "  Status: ${ups_status}  Charge: ${ups_charge}%"
echo ""

# -- Summary --
echo "==============================="
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}, ${YELLOW}%d warnings${NC}\n" "${PASS}" "${FAIL}" "${WARN}"

[ "${FAIL}" -eq 0 ] && exit 0 || exit 1
