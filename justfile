# Multiarch KVM Lab — 16-Port TESmart HKS1601A1U + PiKVM A3
# All commands for building, deploying, and managing the lab

set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default: show available commands
default:
    @just --list --unsorted

# ─── Build & Flash ───────────────────────────────────────────

# Build NixOS SD card image for a host
build-image host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building SD image for {{host}}..."
    mkdir -p images
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
flash-pikvm device variant="v3-hdmi-rpi4" box="true":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{box}}" = "true" ]; then
        suffix="-box"
    else
        suffix=""
    fi
    img="images/pikvm-{{variant}}${suffix}.img"
    url="https://files.pikvm.org/images/{{variant}}/aarch64/{{variant}}-aarch64${suffix}-latest.img.xz"
    if [ ! -f "${img}" ] || [ "$(stat -f%z "${img}" 2>/dev/null || stat -c%s "${img}" 2>/dev/null)" -lt 1000000 ]; then
        echo "Downloading PiKVM image from ${url}..."
        mkdir -p images
        curl -fL --progress-bar "${url}" | xz -d > "${img}"
        echo "Downloaded: $(ls -lh "${img}" | awk '{print $5}')"
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

# Download SD image from latest CI run artifact
download-ci-image host="serial-console":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p images/{{host}}
    echo "Finding latest successful Build SD Image run..."
    run_id=$(gh run list --workflow ci.yml --status success \
        --json databaseId --jq '.[0].databaseId' 2>/dev/null) || true
    if [ -z "${run_id}" ]; then
        echo "No successful run found. Checking in-progress runs..."
        run_id=$(gh run list --workflow ci.yml --status in_progress \
            --json databaseId --jq '.[0].databaseId' 2>/dev/null) || true
    fi
    if [ -z "${run_id}" ]; then
        echo "ERROR: No CI run found. Trigger with: gh workflow run ci.yml"
        exit 1
    fi
    echo "Downloading artifact from run ${run_id}..."
    gh run download "${run_id}" -n {{host}}-sd-image -D images/{{host}}/ || {
        echo "ERROR: Artifact not found. The build may still be in progress."
        echo "Check: gh run view ${run_id}"
        exit 1
    }
    image=$(find images/{{host}}/ -name '*.img*' | head -1)
    echo "Image ready: ${image} ($(ls -lh "${image}" | awk '{print $5}'))"

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

# ─── Testing ──────────────────────────────────────────────────

# Run the full PBT test suite
test *args="":
    nix develop --command python -m pytest tests/ {{args}}

# Run PBT tests with verbose output
test-verbose:
    just test -v --tb=short

# Run PBT tests with JUnit XML output (for CI)
test-ci:
    just test -v --junit-xml=test-results.xml --cov-report=xml:coverage.xml

# ─── Maintenance ─────────────────────────────────────────────

# Update all flake inputs
update:
    nix flake update

# Lint repo Nix source roots
lint:
    nix run nixpkgs#statix -- check flake.nix
    nix run nixpkgs#statix -- check hosts
    nix run nixpkgs#statix -- check modules
    nix run nixpkgs#statix -- check packages
    nix run nixpkgs#deadnix -- flake.nix hosts modules packages

# Format repo Nix source roots
fmt:
    find flake.nix hosts modules packages -name '*.nix' -exec nix run nixpkgs#nixfmt-rfc-style -- {} +

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

# ─── Setup & Bootstrap ──────────────────────────────────────

# Full guided setup: preflight → secrets → nix wiring
setup: preflight setup-secrets setup-nix
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Setup complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next steps:"
    echo "  1. just build-image serial-console"
    echo "  2. just flash serial-console /dev/sdX"
    echo "  3. just flash-pikvm /dev/sdX"
    echo "  4. Boot both Pis, then: just setup-post-boot"
    echo ""

# Phase 0: Check all prerequisites
preflight:
    #!/usr/bin/env bash
    set -uo pipefail
    pass=0; fail=0; warn=0

    check() {
        local label="$1" cmd="$2" extra="${3:-}"
        if eval "$cmd" &>/dev/null; then
            printf "  \033[32m✓\033[0m %s\n" "$label"
            ((pass++))
        elif [ -n "$extra" ]; then
            printf "  \033[33m⚠\033[0m %s — %s\n" "$label" "$extra"
            ((warn++))
        else
            printf "  \033[31m✗\033[0m %s\n" "$label"
            ((fail++))
        fi
    }

    echo "━━━ Preflight Check ━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Tools:"
    check "nix"         "command -v nix"
    check "sops"        "command -v sops"
    check "age"         "command -v age"
    check "ssh-to-age"  "command -v ssh-to-age"
    check "just"        "command -v just"
    check "gh"          "command -v gh"
    check "mkpasswd"    "command -v mkpasswd" "run 'nix develop' to get mkpasswd"

    echo ""
    echo "Keys:"
    check "age key (~/.config/sops/age/keys.txt)" \
          "test -f ~/.config/sops/age/keys.txt"
    check "SSH key (~/.ssh/id_ed25519.pub or id_rsa.pub)" \
          "test -f ~/.ssh/id_ed25519.pub || test -f ~/.ssh/id_rsa.pub"

    echo ""
    echo "Configuration:"
    check ".sops.yaml — age key configured" \
          "! grep -q 'REPLACE_WITH_YOUR_AGE_PUBLIC_KEY' .sops.yaml" \
          "run 'just setup-secrets'"
    check "users.nix — SSH key configured" \
          "! grep -q 'AAAA_REPLACE_WITH_YOUR_KEY' hosts/common/users.nix" \
          "run 'just setup-secrets'"
    check "secrets/pikvm.yaml — encrypted" \
          "grep -q '^sops:' secrets/pikvm.yaml" \
          "run 'just setup-secrets'"
    check "tailscale.nix — authKeyFile wired" \
          "grep -q 'authKeyFile = config.sops' hosts/common/tailscale.nix" \
          "run 'just setup-nix'"
    check "nut-server — sops password wired" \
          "grep -q 'config.sops.secrets.nut-password.path' modules/nut-server/default.nix" \
          "run 'just setup-nix'"
    check "secrets.nix — exists" \
          "test -f hosts/common/secrets.nix" \
          "run 'just setup-nix'"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  \033[32m%d passed\033[0m  " "$pass"
    [ "$warn" -gt 0 ] && printf "\033[33m%d warnings\033[0m  " "$warn"
    [ "$fail" -gt 0 ] && printf "\033[31m%d failed\033[0m" "$fail"
    echo ""

    if [ "$fail" -gt 0 ]; then
        echo "  Fix failures above before continuing."
        exit 1
    fi

# Phase 1: Bootstrap identity and secrets (interactive)
setup-secrets tskey="":
    #!/usr/bin/env bash
    set -euo pipefail

    echo "━━━ Secrets Bootstrap ━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # ── Backup originals ──
    mkdir -p .setup-backup
    for f in .sops.yaml hosts/common/users.nix secrets/pikvm.yaml; do
        if [ -f "$f" ] && [ ! -f ".setup-backup/$(basename "$f")" ]; then
            cp "$f" ".setup-backup/$(basename "$f")"
        fi
    done

    # ── 1. Age public key ──
    if ! test -f ~/.config/sops/age/keys.txt; then
        echo "ERROR: No age key found at ~/.config/sops/age/keys.txt"
        echo "Generate one with: age-keygen -o ~/.config/sops/age/keys.txt"
        exit 1
    fi
    age_pubkey=$(age-keygen -y ~/.config/sops/age/keys.txt)
    echo "  Age public key: ${age_pubkey}"

    # ── 2. SSH public key ──
    ssh_pubkey=""
    for keyfile in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        if [ -f "$keyfile" ]; then
            ssh_pubkey=$(cat "$keyfile")
            echo "  SSH public key:  ${keyfile}"
            break
        fi
    done
    if [ -z "$ssh_pubkey" ]; then
        echo "ERROR: No SSH public key found in ~/.ssh/"
        echo "Generate one with: ssh-keygen -t ed25519"
        exit 1
    fi

    # ── 3. Tailscale auth key ──
    ts_key="{{tskey}}"
    if [ -z "$ts_key" ]; then
        echo ""
        echo "  Tailscale auth key (from https://login.tailscale.com/admin/settings/keys)"
        echo "  Must be reusable. Leave blank to skip (manual 'tailscale up' after boot)."
        printf "  > "
        read -r ts_key
    fi

    # ── 4. PiKVM root password ──
    echo ""
    echo "  PiKVM root password (will be hashed with SHA-512):"
    printf "  > "
    read -rs root_pw
    echo ""
    if [ -z "$root_pw" ]; then
        echo "ERROR: Root password cannot be empty"
        exit 1
    fi
    root_hash=$(echo "$root_pw" | mkpasswd -m sha-512 --stdin)

    # ── 5. kvmd admin password ──
    echo "  kvmd admin password (leave blank to generate random 16-char):"
    printf "  > "
    read -rs kvmd_pw
    echo ""
    if [ -z "$kvmd_pw" ]; then
        kvmd_pw=$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo "  Generated kvmd password (save this): ${kvmd_pw}"
    fi

    echo ""
    echo "Applying configuration..."

    # ── Write .sops.yaml ──
    if grep -q 'REPLACE_WITH_YOUR_AGE_PUBLIC_KEY' .sops.yaml; then
        sed -i.bak "s|age1REPLACE_WITH_YOUR_AGE_PUBLIC_KEY|${age_pubkey}|" .sops.yaml
        rm -f .sops.yaml.bak
        echo "  ✓ .sops.yaml — age key configured"
    else
        echo "  ⊘ .sops.yaml — already configured, skipping"
    fi

    # ── Write users.nix ──
    if grep -q 'AAAA_REPLACE_WITH_YOUR_KEY' hosts/common/users.nix; then
        # Escape the SSH key for sed (contains / and +)
        escaped_key=$(printf '%s\n' "$ssh_pubkey" | sed 's/[&/\]/\\&/g')
        sed -i.bak "s|ssh-ed25519 AAAA_REPLACE_WITH_YOUR_KEY admin@workstation|${escaped_key}|g" \
            hosts/common/users.nix
        rm -f hosts/common/users.nix.bak
        echo "  ✓ users.nix — SSH keys configured"
    else
        echo "  ⊘ users.nix — already configured, skipping"
    fi

    # ── Create authorized_keys for PiKVM preseed ──
    preseed_dir="hosts/pikvm-primary/preseed"
    if [ ! -f "${preseed_dir}/authorized_keys" ] || \
       grep -q 'AAAA_REPLACE_WITH_YOUR_KEY' "${preseed_dir}/authorized_keys" 2>/dev/null; then
        printf "# SSH public keys for PiKVM root access\n%s\n" "$ssh_pubkey" \
            > "${preseed_dir}/authorized_keys"
        echo "  ✓ preseed/authorized_keys — created with SSH key"
    else
        echo "  ⊘ preseed/authorized_keys — already exists, skipping"
    fi

    # ── Write secrets/pikvm.yaml ──
    if grep -q '^sops:' secrets/pikvm.yaml; then
        echo "  ⊘ secrets/pikvm.yaml — already encrypted, skipping"
        echo "    To re-edit: just edit-secret pikvm.yaml"
    else
        # Replace placeholders in the plaintext template
        if [ -n "$ts_key" ]; then
            sed -i.bak "s|tskey-auth-REPLACE_WITH_YOUR_KEY|${ts_key}|" secrets/pikvm.yaml
        else
            echo "  ⚠ Tailscale key skipped — you'll need manual 'tailscale up' after boot"
        fi

        # Use | delimiter to avoid conflicts with $ in hash
        sed -i.bak "s|\\\$6\\\$REPLACE_WITH_HASH|${root_hash}|" secrets/pikvm.yaml
        sed -i.bak "s|REPLACE_WITH_PASSWORD|${kvmd_pw}|" secrets/pikvm.yaml
        rm -f secrets/pikvm.yaml.bak

        # Encrypt immediately
        echo "  Encrypting secrets/pikvm.yaml..."
        sops -e -i secrets/pikvm.yaml

        # Verify roundtrip
        if sops -d secrets/pikvm.yaml > /dev/null 2>&1; then
            echo "  ✓ secrets/pikvm.yaml — encrypted and verified"
        else
            echo "  ✗ secrets/pikvm.yaml — encryption verification failed!"
            exit 1
        fi
    fi

    echo ""
    echo "  Secrets bootstrap complete."
    echo ""

# Phase 2: Wire sops into NixOS modules (idempotent)
setup-nix:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "━━━ NixOS Sops Wiring ━━━━━━━━━━━━━━━━━━━"
    echo ""

    changed=0

    # Check secrets.nix exists (created by this repo, not by this recipe)
    if [ -f hosts/common/secrets.nix ]; then
        echo "  ✓ hosts/common/secrets.nix exists"
    else
        echo "  ✗ hosts/common/secrets.nix missing — this shouldn't happen"
        exit 1
    fi

    # Check flake.nix has secrets.nix in module list
    if grep -q 'secrets.nix' flake.nix; then
        echo "  ✓ flake.nix — secrets.nix in module list"
    else
        echo "  ✗ flake.nix — secrets.nix not in module list (add manually)"
        exit 1
    fi

    # Check tailscale.nix has authKeyFile uncommented
    if grep -q '# authKeyFile' hosts/common/tailscale.nix; then
        echo "  ✗ tailscale.nix — authKeyFile still commented"
        exit 1
    elif grep -q 'authKeyFile = config.sops' hosts/common/tailscale.nix; then
        echo "  ✓ tailscale.nix — authKeyFile wired to sops"
    fi

    # Check nut-server has sops refs
    if grep -q '"/run/secrets/nut-password"' modules/nut-server/default.nix; then
        echo "  ✗ nut-server — still using hardcoded placeholder path"
        exit 1
    elif grep -q 'config.sops.secrets.nut-password.path' modules/nut-server/default.nix; then
        echo "  ✓ nut-server — password wired to sops"
    fi

    echo ""
    echo "  All NixOS modules correctly wired."
    echo ""
    echo "  Validating flake outputs..."
    nix flake show 2>&1 | grep -E '(nixosConfigurations|images|packages|deploy)' || true
    echo ""

# Show current setup progress
setup-status:
    #!/usr/bin/env bash
    set -uo pipefail

    echo "━━━ Setup Status ━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    status() {
        local label="$1" check="$2"
        if eval "$check" &>/dev/null; then
            printf "  \033[32m✓\033[0m %s\n" "$label"
        else
            printf "  \033[31m✗\033[0m %s\n" "$label"
        fi
    }

    echo "Phase 0 — Prerequisites:"
    status "nix available"        "command -v nix"
    status "sops available"       "command -v sops"
    status "age key exists"       "test -f ~/.config/sops/age/keys.txt"
    status "SSH key exists"       "test -f ~/.ssh/id_ed25519.pub || test -f ~/.ssh/id_rsa.pub"

    echo ""
    echo "Phase 1 — Secrets:"
    status ".sops.yaml configured"       "! grep -q 'REPLACE_WITH_YOUR_AGE_PUBLIC_KEY' .sops.yaml"
    status "users.nix SSH keys set"      "! grep -q 'AAAA_REPLACE_WITH_YOUR_KEY' hosts/common/users.nix"
    status "preseed/authorized_keys"     "test -f hosts/pikvm-primary/preseed/authorized_keys && ! grep -q 'AAAA_REPLACE' hosts/pikvm-primary/preseed/authorized_keys"
    status "secrets/pikvm.yaml encrypted" "grep -q '^sops:' secrets/pikvm.yaml"

    echo ""
    echo "Phase 2 — NixOS Wiring:"
    status "secrets.nix exists"           "test -f hosts/common/secrets.nix"
    status "flake.nix includes secrets"   "grep -q 'secrets.nix' flake.nix"
    status "tailscale authKeyFile wired"  "grep -q 'authKeyFile = config.sops' hosts/common/tailscale.nix"
    status "nut-server sops password"     "grep -q 'config.sops.secrets.nut-password.path' modules/nut-server/default.nix"

    echo ""
    echo "Phase 4 — Images:"
    status "serial-console image built"   "test -d images/serial-console"

    echo ""
    echo "Phase 5 — Post-Boot:"
    status "serial-console reachable"     "ssh -o ConnectTimeout=2 -o BatchMode=yes admin@\$(just _resolve-host serial-console) true 2>/dev/null"
    status "pikvm-primary reachable"      "ssh -o ConnectTimeout=2 -o BatchMode=yes root@\$(just _resolve-host pikvm-primary) true 2>/dev/null"
    status "Host age keys in .sops.yaml"  "! grep -q 'REPLACE_AFTER_FIRST_BOOT' .sops.yaml"
    status "Serial devices mapped"        "! grep -q 'REPLACE_WITH_ACTUAL_ID' hosts/serial-console/default.nix"

    echo ""
    echo "Phase 6 — Validation:"
    status "Health check passes"          "just health 2>/dev/null"
    echo ""

# Phase 5: Post-boot setup (requires running hardware)
setup-post-boot:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "━━━ Post-Boot Setup ━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    serial_host=$(just _resolve-host serial-console)
    pikvm_host=$(just _resolve-host pikvm-primary)

    # ── Wait for SSH ──
    echo "Waiting for hosts to come online..."
    for host_label in "serial-console:${serial_host}:admin" "pikvm-primary:${pikvm_host}:root"; do
        IFS=: read -r name addr user <<< "$host_label"
        printf "  Waiting for %s (%s)... " "$name" "$addr"
        for i in $(seq 1 20); do
            if ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
                   "${user}@${addr}" true 2>/dev/null; then
                printf "\033[32monline\033[0m\n"
                break
            fi
            if [ "$i" -eq 20 ]; then
                printf "\033[31mtimeout\033[0m\n"
                echo "    Could not reach ${name}. Check network and try again."
            fi
            sleep 3
        done
    done

    echo ""

    # ── Capture host age keys ──
    echo "Capturing host age keys..."
    serial_age=$(ssh-keyscan -t ed25519 "${serial_host}" 2>/dev/null | ssh-to-age 2>/dev/null || echo "")
    pikvm_age=""  # PiKVM doesn't need age key (Arch, not sops-nix managed)

    if [ -n "$serial_age" ]; then
        echo ""
        echo "  serial-console age key:"
        echo "    ${serial_age}"
        echo ""
        echo "  Add this to .sops.yaml by uncommenting and replacing line 11:"
        echo "    - &serial_console ${serial_age}"
        echo ""
        echo "  Then run: just rekey-secrets"
    else
        echo "  ⚠ Could not capture serial-console host key"
    fi

    echo ""

    # ── Discover serial devices ──
    echo "Discovering USB serial devices on serial-console..."
    echo ""
    ssh "admin@${serial_host}" 'bash -s' < scripts/serial-discover.sh 2>/dev/null || {
        echo "  ⚠ Could not run serial discovery. Run manually:"
        echo "    just discover-serial"
    }

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Remaining manual steps:"
    echo "  1. Update .sops.yaml with host age key (shown above)"
    echo "  2. Run: just rekey-secrets"
    echo "  3. Update hosts/serial-console/default.nix with device IDs from discovery output"
    echo "  4. Run: just deploy serial-console"
    echo "  5. Run: just validate"
    echo ""

# Phase 6: End-to-end validation
validate:
    #!/usr/bin/env bash
    set -uo pipefail
    pass=0; fail=0

    check() {
        local label="$1"
        shift
        if "$@" &>/dev/null; then
            printf "  \033[32m✓\033[0m %s\n" "$label"
            ((++pass))
        else
            printf "  \033[31m✗\033[0m %s\n" "$label"
            ((++fail))
        fi
    }

    echo "━━━ Validation ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    serial_host=$(just _resolve-host serial-console)
    pikvm_host=$(just _resolve-host pikvm-primary)

    echo "Connectivity:"
    check "SSH to serial-console" ssh -o ConnectTimeout=3 -o BatchMode=yes "admin@${serial_host}" true
    check "SSH to pikvm-primary"  ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${pikvm_host}" true

    echo ""
    echo "Tailscale:"
    check "serial-console on Tailscale" ssh -o ConnectTimeout=3 -o BatchMode=yes "admin@${serial_host}" \
          "tailscale status --json | grep -q serial-console"
    check "pikvm-primary on Tailscale"  ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${pikvm_host}" \
          "tailscale status --json | grep -q pikvm-primary"

    echo ""
    echo "Services:"
    check "ser2net running"   ssh -o ConnectTimeout=3 -o BatchMode=yes "admin@${serial_host}" \
          "systemctl is-active ser2net"
    check "NUT server running" ssh -o ConnectTimeout=3 -o BatchMode=yes "admin@${serial_host}" \
          "systemctl is-active nut-server"
    check "kvmd running"      ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${pikvm_host}" \
          "systemctl is-active kvmd"

    echo ""
    echo "TESmart KVM:"
    export TESMART_HOST="${TESMART_HOST:-10.0.0.50}"
    export TESMART_PORT="${TESMART_PORT:-5000}"
    check "TESmart reachable (TCP ${TESMART_PORT})" \
          python3 -c 'import os, socket; s = socket.create_connection((os.environ["TESMART_HOST"], int(os.environ["TESMART_PORT"])), 3); s.close()'
    # Try to query current port if tesmart-ctl is available
    if command -v tesmart-ctl &>/dev/null; then
        port=$(tesmart-ctl --host "${TESMART_HOST}" --port "${TESMART_PORT}" get 2>/dev/null || echo "?")
        echo "  Current KVM port: ${port}"
    elif [ -x packages/tesmart-ctl/tesmart_ctl.py ]; then
        port=$(python3 packages/tesmart-ctl/tesmart_ctl.py --host "${TESMART_HOST}" --port "${TESMART_PORT}" get 2>/dev/null || echo "?")
        echo "  Current KVM port: ${port}"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  \033[32m%d passed\033[0m" "$pass"
    [ "$fail" -gt 0 ] && printf "  \033[31m%d failed\033[0m" "$fail"
    echo ""
    [ "$fail" -gt 0 ] && exit 1 || true
