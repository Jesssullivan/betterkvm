# Multiarch KVM Lab
# All commands for building, deploying, and managing the lab

set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default: show available commands
default:
    @just --list --unsorted

# ─── Build & Flash ───────────────────────────────────────────

# Build NixOS SD card image for a host (cross-compiled on x86_64)
build-image host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building SD image for {{host}}..."
    nix build ".#images.{{host}}" --out-link "images/{{host}}"
    image=$(find images/{{host}}/ -name '*.img*' | head -1)
    echo "Image built: ${image}"
    ls -lh "${image}"

# Flash a built image to an SD card device
flash host device:
    ./scripts/flash-sd.sh "$(find images/{{host}}/ -name '*.img*' | head -1)" {{device}}

# Build and flash in one step
build-and-flash host device: (build-image host) (flash host device)

# Download and flash PiKVM OS image for the KVM Pi
flash-pikvm device variant="v3-hdmi-rpi4-box":
    #!/usr/bin/env bash
    set -euo pipefail
    img="images/pikvm-{{variant}}.img"
    url="https://files.pikvm.org/images/{{variant}}/{{variant}}-aarch64-latest.img.xz"
    if [ ! -f "${img}" ]; then
        echo "Downloading PiKVM image..."
        mkdir -p images
        curl -L "${url}" | xz -d > "${img}"
    fi
    ./scripts/flash-sd.sh "${img}" {{device}}

# ─── Remote Deployment ───────────────────────────────────────

# Deploy NixOS configuration to a running Pi via deploy-rs
deploy host:
    deploy-rs ".#{{host}}"

# Deploy to all NixOS hosts
deploy-all:
    deploy-rs .

# Quick deploy using nixos-rebuild (no deploy-rs needed)
rebuild host:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(just _resolve-host {{host}})
    nixos-rebuild switch \
        --flake ".#{{host}}" \
        --target-host "root@${target}" \
        --use-remote-sudo

# Deploy PiKVM override.yaml config (Arch-based, not NixOS)
deploy-pikvm:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(just _resolve-host pikvm-primary)
    echo "Deploying PiKVM config to ${target}..."
    ssh "root@${target}" 'rw'
    scp hosts/pikvm-primary/kvmd/override.yaml "root@${target}:/etc/kvmd/override.yaml"
    ssh "root@${target}" 'systemctl restart kvmd && ro'
    echo "PiKVM config deployed and kvmd restarted."

# ─── TESmart KVM Switch ─────────────────────────────────────

# Switch TESmart to port N (1-8 or 1-16)
switch-port n:
    python3 packages/tesmart-ctl/tesmart_ctl.py set {{n}}

# Query current active port on TESmart switch
current-port:
    python3 packages/tesmart-ctl/tesmart_ctl.py get

# Toggle TESmart buzzer (on/off)
buzzer state:
    python3 packages/tesmart-ctl/tesmart_ctl.py buzzer {{state}}

# ─── Serial Console ─────────────────────────────────────────

# Connect to a named serial console via ser2net
serial name port="":
    #!/usr/bin/env bash
    set -euo pipefail
    console_host=$(just _resolve-host serial-console)
    if [ -n "{{port}}" ]; then
        telnet "${console_host}" {{port}}
    else
        case "{{name}}" in
            riscv1)   telnet "${console_host}" 3001 ;;
            riscv2)   telnet "${console_host}" 3002 ;;
            arm1)     telnet "${console_host}" 3003 ;;
            server1)  telnet "${console_host}" 3004 ;;
            server2)  telnet "${console_host}" 3005 ;;
            server3)  telnet "${console_host}" 3006 ;;
            *)
                echo "Unknown console '{{name}}'. Known: riscv1, riscv2, arm1, server1, server2, server3"
                echo "Or specify port directly: just serial {{name}} <port>"
                exit 1
                ;;
        esac
    fi

# Discover USB serial devices on the serial-console Pi
discover-serial:
    ./scripts/serial-discover.sh

# ─── Status & Health ─────────────────────────────────────────

# Show status of all lab nodes
status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== KVM Lab Status ==="
    echo ""
    for host in pikvm-primary serial-console; do
        addr=$(just _resolve-host "${host}" 2>/dev/null || echo "UNRESOLVED")
        if [ "${addr}" = "UNRESOLVED" ]; then
            printf "  %-20s %s\n" "${host}" "UNRESOLVED"
            continue
        fi
        if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${addr}" true 2>/dev/null; then
            uptime=$(ssh -o ConnectTimeout=3 "root@${addr}" 'uptime -p' 2>/dev/null || echo "?")
            printf "  %-20s %-15s UP (%s)\n" "${host}" "${addr}" "${uptime}"
        else
            printf "  %-20s %-15s DOWN\n" "${host}" "${addr}"
        fi
    done
    echo ""
    echo "=== TESmart Switch ==="
    just current-port 2>/dev/null || echo "  Switch unreachable"
    echo ""
    echo "=== Tailscale ==="
    tailscale status 2>/dev/null | grep -E "pikvm|serial|monitor|kvm" || echo "  No lab nodes on tailnet"

# Run comprehensive health checks
health:
    ./scripts/health-check.sh

# Show Tailscale network status
tailscale-status:
    tailscale status

# Show UPS status from NUT
nut-status:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(just _resolve-host serial-console)
    ssh "root@${target}" 'upsc rack-ups@localhost 2>/dev/null' || \
        echo "NUT unreachable. Is the serial-console Pi running?"

# ─── Maintenance ─────────────────────────────────────────────

# Update all flake inputs
update:
    nix flake update

# Lint all Nix files
lint:
    nix run nixpkgs#statix -- check .
    nix run nixpkgs#deadnix -- .

# Format all Nix files
fmt:
    nix run nixpkgs#nixfmt -- .

# Check flake
check:
    nix flake check

# Show flake outputs
show:
    nix flake show

# Re-encrypt secrets after adding new host keys
rekey-secrets:
    find secrets -name '*.yaml' -exec sops updatekeys {} \;

# Edit a secret file
edit-secret file:
    sops secrets/{{file}}

# Backup configs from all running Pis
backup-configs:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${dir}"
    for host in pikvm-primary serial-console; do
        addr=$(just _resolve-host "${host}" 2>/dev/null) || continue
        echo "Backing up ${host}..."
        mkdir -p "${dir}/${host}"
        ssh "root@${addr}" 'tar czf - /etc/kvmd /etc/nixos 2>/dev/null' \
            > "${dir}/${host}/config.tar.gz" 2>/dev/null || true
    done
    echo "Backups saved to ${dir}/"

# SSH to a lab host
ssh host:
    #!/usr/bin/env bash
    target=$(just _resolve-host {{host}})
    ssh "root@${target}"

# Enter the nix dev shell
dev:
    nix develop

# ─── Internal Helpers ─────────────────────────────────────────

# Resolve host to IP/hostname (Tailscale or env override)
[private]
_resolve-host host:
    #!/usr/bin/env bash
    case "{{host}}" in
        pikvm-primary)  echo "${PIKVM_HOST:-pikvm-primary}" ;;
        serial-console) echo "${SERIAL_HOST:-serial-console}" ;;
        monitor-node)   echo "${MONITOR_HOST:-monitor-node}" ;;
        *) echo "{{host}}" ;;
    esac
