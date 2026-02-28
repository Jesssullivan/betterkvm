# Multiarch KVM Lab — 16-Port TESmart HKS1601A1U + PiKVM A3
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

# Download, flash, and preseed PiKVM OS image
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
    echo ""
    echo "Preseeding PiKVM configuration..."
    just preseed-pikvm {{device}}

# Preseed a flashed PiKVM SD card with auth, config, and secrets
preseed-pikvm device:
    #!/usr/bin/env bash
    set -euo pipefail
    preseed_dir="hosts/pikvm-primary/preseed"
    override_file="hosts/pikvm-primary/kvmd/override.yaml"

    # Determine OS for mount commands
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: find the boot partition (FAT32, usually disk<N>s1)
        boot_part="${{device}}s1"
        mount_point="/Volumes/boot"
        echo "Mounting ${boot_part}..."
        diskutil mount "${boot_part}" || {
            echo "ERROR: Could not mount ${boot_part}. Is the SD card inserted?"
            exit 1
        }
    else
        # Linux: mount the first partition
        boot_part="${{device}}1"
        mount_point=$(mktemp -d)
        echo "Mounting ${boot_part} at ${mount_point}..."
        sudo mount "${boot_part}" "${mount_point}"
    fi

    cleanup() {
        echo "Unmounting boot partition..."
        if [[ "$(uname)" == "Darwin" ]]; then
            diskutil unmount "${mount_point}" 2>/dev/null || true
        else
            sudo umount "${mount_point}" 2>/dev/null || true
            rmdir "${mount_point}" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    # Copy preseed files
    echo "Copying preseed files..."
    cp "${preseed_dir}/pikvm.txt" "${mount_point}/pikvm.txt"

    # Copy preseed scripts
    mkdir -p "${mount_point}/pikvm-scripts.d"
    cp "${preseed_dir}/pikvm-scripts.d/"*.sh "${mount_point}/pikvm-scripts.d/"
    chmod +x "${mount_point}/pikvm-scripts.d/"*.sh

    # Copy override.yaml
    cp "${override_file}" "${mount_point}/override.yaml"

    # Copy SSH authorized_keys (use local copy, or fall back to .example)
    if [ -f "${preseed_dir}/authorized_keys" ]; then
        cp "${preseed_dir}/authorized_keys" "${mount_point}/authorized_keys"
    elif [ -f "${preseed_dir}/authorized_keys.example" ]; then
        echo "WARNING: Using authorized_keys.example — copy to authorized_keys and add your real keys"
        cp "${preseed_dir}/authorized_keys.example" "${mount_point}/authorized_keys"
    else
        echo "WARNING: No authorized_keys found, skipping SSH key preseed"
    fi

    # Decrypt and inject secrets
    echo "Decrypting secrets..."
    secrets_dir="${mount_point}/pikvm-secrets"
    mkdir -p "${secrets_dir}"

    sops -d --extract '["pikvm_root_password_hash"]' secrets/pikvm.yaml \
        > "${secrets_dir}/root-password-hash"
    sops -d --extract '["kvmd_admin_password"]' secrets/pikvm.yaml \
        > "${secrets_dir}/kvmd-admin-password"
    sops -d --extract '["tailscale_authkey"]' secrets/pikvm.yaml \
        > "${secrets_dir}/tailscale-authkey"

    echo "Preseed complete. Files on boot partition:"
    ls -la "${mount_point}/pikvm.txt" \
           "${mount_point}/override.yaml" \
           "${mount_point}/authorized_keys" \
           "${mount_point}/pikvm-scripts.d/" \
           "${mount_point}/pikvm-secrets/"

# Download pre-built SD image from GitHub releases
download-image host version="latest":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images
    if [ "{{version}}" = "latest" ]; then
        echo "Fetching latest release..."
        tag=$(gh release view --json tagName --jq '.tagName') || {
            echo "ERROR: No release found. Build locally with: just build-image {{host}}"
            exit 1
        }
    else
        tag="{{version}}"
    fi
    echo "Downloading betterkvm-{{host}}-${tag}.img.zst..."
    gh release download "${tag}" --pattern "*{{host}}*" --dir images/ --clobber
    zst_file=$(find images/ -name "betterkvm-{{host}}-${tag}.img.zst" | head -1)
    if [ -z "${zst_file}" ]; then
        echo "ERROR: No image artifact found for {{host}} in release ${tag}"
        exit 1
    fi
    echo "Decompressing..."
    zstd -d "${zst_file}" -o "images/{{host}}.img" --force
    echo "Image ready: images/{{host}}.img"
    ls -lh "images/{{host}}.img"

# Download pre-built image and flash to SD card
download-and-flash host device version="latest": (download-image host version)
    ./scripts/flash-sd.sh "images/{{host}}.img" {{device}}

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

# Switch TESmart to port N (1-16)
switch-port n:
    python3 packages/tesmart-ctl/tesmart_ctl.py set {{n}}

# Query current active port on TESmart switch
current-port:
    python3 packages/tesmart-ctl/tesmart_ctl.py get

# Toggle TESmart buzzer (on/off)
buzzer state:
    python3 packages/tesmart-ctl/tesmart_ctl.py buzzer {{state}}

# Toggle TESmart input auto-detection (on/off)
tesmart-autodetect state:
    python3 packages/tesmart-ctl/tesmart_ctl.py autodetect {{state}}

# Set TESmart LCD timeout (0=always on, 10, 30 seconds)
tesmart-lcd seconds:
    python3 packages/tesmart-ctl/tesmart_ctl.py lcd {{seconds}}

# Query TESmart switch info (active port + network config)
tesmart-info:
    python3 packages/tesmart-ctl/tesmart_ctl.py info

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
            honey)             telnet "${console_host}" 3001 ;;
            bumble)            telnet "${console_host}" 3002 ;;
            petting-zoo-mini)  telnet "${console_host}" 3003 ;;
            xoxd-bates)        telnet "${console_host}" 3004 ;;
            yoga)              telnet "${console_host}" 3005 ;;
            mbp-13)            telnet "${console_host}" 3006 ;;
            betsy)             telnet "${console_host}" 3007 ;;
            musey)             telnet "${console_host}" 3008 ;;
            sdr-1)             telnet "${console_host}" 3009 ;;
            g2-1)              telnet "${console_host}" 3010 ;;
            g2-2)              telnet "${console_host}" 3011 ;;
            t-deck)            telnet "${console_host}" 3012 ;;
            tdeck-pro)         telnet "${console_host}" 3013 ;;
            port14)            telnet "${console_host}" 3014 ;;
            port15)            telnet "${console_host}" 3015 ;;
            port16)            telnet "${console_host}" 3016 ;;
            *)
                echo "Unknown console '{{name}}'."
                echo "Known: honey, bumble, petting-zoo-mini, xoxd-bates, yoga, mbp-13,"
                echo "       betsy, musey, sdr-1, g2-1, g2-2, t-deck, tdeck-pro,"
                echo "       port14, port15, port16"
                echo "Or specify port directly: just serial {{name}} <port>"
                exit 1
                ;;
        esac
    fi

# Discover USB serial devices on the serial-console Pi
discover-serial:
    ./scripts/serial-discover.sh

# ─── Subtree Management ─────────────────────────────────────

# Update vendor subtrees from upstream (all or one prefix)
subtree-update target="all":
    #!/usr/bin/env bash
    set -euo pipefail
    update_subtree() {
        local prefix="$1" remote="$2" branch="$3"
        echo "Updating ${prefix} from ${remote}/${branch}..."
        git subtree pull --prefix="${prefix}" "${remote}" "${branch}" --squash
    }
    case "{{target}}" in
        all)
            update_subtree vendor/kvmd pikvm-kvmd master
            update_subtree vendor/ustreamer pikvm-ustreamer master
            update_subtree vendor/os pikvm-os master
            ;;
        vendor/kvmd)      update_subtree vendor/kvmd pikvm-kvmd master ;;
        vendor/ustreamer) update_subtree vendor/ustreamer pikvm-ustreamer master ;;
        vendor/os)        update_subtree vendor/os pikvm-os master ;;
        *)
            echo "Unknown subtree '{{target}}'. Known: all, vendor/kvmd, vendor/ustreamer, vendor/os"
            exit 1
            ;;
    esac

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

# Lint all Nix files (excludes vendor/)
lint:
    nix run nixpkgs#statix -- check . --ignore vendor/
    nix run nixpkgs#deadnix -- --exclude vendor/ .

# Format all Nix files (excludes vendor/)
fmt:
    find . -name '*.nix' -not -path './vendor/*' -exec nix run nixpkgs#nixfmt -- {} +

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
