# BetterKVM: Justfile-Driven Setup, Flash, and Validation Flow

## Summary

Adds a phased, guided setup flow to the existing justfile. New users currently must manually find and replace ~30 placeholder values across 6+ files. The new recipes automate that entirely: detect local keys, prompt for secrets, wire sops-nix into Nix modules, and validate the result.

Touches 8 existing files, creates 2 new files.

---

## Complete Recipe Inventory (new additions)

| Recipe | Signature | Phase | Purpose |
|--------|-----------|-------|---------|
| `preflight` | (none) | 0 | Check all prerequisites |
| `setup-secrets` | `ssh_key_path="" tailscale_key="" kvmd_password=""` | 1 | Bootstrap identity and secrets |
| `setup-nix` | (none) | 2 | Wire sops into NixOS modules |
| `setup` | (none) | 0-2 | Chain preflight + secrets + nix |
| `setup-status` | (none) | all | Show progress checklist |
| `build-all` | (none) | 3 | Build all host images |
| `flash-with-check` | `host device` | 4 | Flash with preflight guard |
| `setup-post-boot` | (none) | 5 | Post-boot host key capture + serial discovery |
| `setup-host-keys` | `host` | 5 | Capture one host's age key |
| `validate` | (none) | 6 | Full end-to-end validation |

---

## File Modifications

### Files to MODIFY

| File | Changes |
|------|---------|
| `justfile` | Append ~300 lines of new setup/validation recipes |
| `.sops.yaml` | `setup-secrets` replaces age key placeholder with real key |
| `secrets/pikvm.yaml` | `setup-secrets` populates values + sops-encrypts |
| `hosts/common/users.nix` | `setup-secrets` replaces SSH key placeholders |
| `hosts/common/tailscale.nix` | `setup-nix` uncomments authKeyFile line |
| `modules/nut-server/default.nix` | `setup-nix` replaces hardcoded paths with sops refs |
| `flake.nix` | `setup-nix` adds secrets.nix to mkPiSystem modules + adds `whois` to devShell |

### Files to CREATE

| File | Purpose |
|------|---------|
| `hosts/common/secrets.nix` | Centralized sops.secrets declarations |
| `.gitignore` | Protect against committing decrypted secrets/backups |

---

## Phase 0: Preflight — `just preflight`

Checks all prerequisites and reports setup progress.

### What it checks

1. **Required tools**: `nix`, `sops`, `age`, `ssh-to-age`, `just`, `git` -- FAIL if missing
2. **Optional tools**: `deploy-rs`, `gh`, `zstd`, `mkpasswd` -- WARN if missing
3. **Age key**: exists at `~/.config/sops/age/keys.txt`, can extract public key
4. **SSH key**: exists in `~/.ssh/` (tries ed25519, rsa, ecdsa)
5. **Nix flake**: `nix flake metadata .` succeeds
6. **Setup status**: Checks each placeholder file, reports PASS/WARN per file

### Output format

Uses color-coded PASS/FAIL/WARN like the existing `scripts/health-check.sh`:
```
  PASS  nix found: /nix/store/.../bin/nix
  PASS  sops found: /nix/store/.../bin/sops
  WARN  mkpasswd not found (install via nix develop)
  PASS  Age key found: age1wc2s9pfju7hau...
  WARN  .sops.yaml still has placeholder age key
```

Exits nonzero if any required check fails. Warnings do not block.

---

## Phase 1: Secrets Bootstrap — `just setup-secrets`

### Signature

```
setup-secrets ssh_key_path="" tailscale_key="" kvmd_password=""
```

All three arguments are optional. When omitted, auto-detects (age, SSH) or prompts interactively (Tailscale key, root password, kvmd password).

### Step-by-step logic

```
1. AUTO-DETECT age public key
   - Read ~/.config/sops/age/keys.txt
   - Extract via: grep 'public key:' or age-keygen -y
   - ABORT if missing (with exact command to create it)

2. AUTO-DETECT SSH public key
   - If ssh_key_path argument provided, use it
   - Else scan ~/.ssh/id_ed25519.pub, id_rsa.pub, id_ecdsa.pub
   - ABORT if none found

3. COLLECT Tailscale auth key
   - If tailscale_key argument provided, use it
   - Else prompt interactively
   - Validate prefix "tskey-" (warn if wrong, don't block)

4. GENERATE root password hash
   - Prompt for password (hidden input, confirm)
   - Hash via: mkpasswd -m sha-512 (or python3 crypt fallback)

5. COLLECT kvmd admin password
   - If kvmd_password argument provided, use it
   - Else prompt interactively (hidden input)

6. BACKUP files with local changes
   - For each target file: check git diff, copy to .setup-backup if dirty

7. WRITE .sops.yaml
   - sed: "age1REPLACE_WITH_YOUR_AGE_PUBLIC_KEY" -> real age public key
   - Skip if already configured (idempotent)

8. WRITE hosts/common/users.nix
   - sed: replace both "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_KEY admin@workstation"
     with actual SSH public key string
   - Skip if already configured

9. CREATE hosts/pikvm-primary/preseed/authorized_keys
   - Write SSH public key (one line)
   - This is the file preseed-pikvm copies to the SD boot partition

10. WRITE secrets/pikvm.yaml
    - sed: "tskey-auth-REPLACE_WITH_YOUR_KEY" -> real key
    - sed: "$6$REPLACE_WITH_HASH" -> real hash
    - sed: "REPLACE_WITH_PASSWORD" -> real password
    - Skip if already configured or encrypted

11. ENCRYPT secrets/pikvm.yaml
    - sops --encrypt --in-place secrets/pikvm.yaml
    - Skip if already encrypted (check for "^sops:" marker)

12. VERIFY
    - sops -d --extract '["tailscale_authkey"]' secrets/pikvm.yaml > /dev/null

13. REPORT what was done + next step
```

### Non-interactive mode

All interactive values can be passed as arguments:
```bash
just setup-secrets "" "tskey-auth-kFoo..." "hunter2"
# First arg empty = auto-detect SSH key
# Root password still prompts (security: no password on command line)
```

Root password always prompts interactively for security. There is no argument for it because putting passwords on the command line exposes them in shell history and process listings.

### sed strategy

Uses `|` as sed delimiter (not `/`) since paths and keys contain `/`. Every `sed -i` call branches on `uname` for macOS compatibility:
```bash
if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "s|PLACEHOLDER|REPLACEMENT|g" file
else
    sed -i "s|PLACEHOLDER|REPLACEMENT|g" file
fi
```

This matches the macOS-awareness pattern already present in the `preseed-pikvm` recipe.

---

## Phase 2: NixOS Wiring — `just setup-nix`

Makes four changes to wire sops-nix secrets into the NixOS configuration.

### Change 1: Create `hosts/common/secrets.nix` (NEW FILE)

```nix
{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/pikvm.yaml;
    defaultSopsFormat = "yaml";

    # Age key derived from host SSH key (sops-nix default behavior)
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      tailscale-auth-key = {
        key = "tailscale_authkey";
        restartUnits = [ "tailscaled.service" ];
      };
      nut-password = {
        key = "kvmd_admin_password";
        owner = "nut";
        group = "nut";
      };
    };
  };
}
```

**Design rationale**: Centralizing sops declarations in one module rather than sprinkling them across tailscale.nix and nut-server is better because:
- `defaultSopsFile` and `age.sshKeyPaths` are set exactly once
- All secret references are auditable in one file
- Consuming modules just use `config.sops.secrets.<name>.path`
- Matches the pattern used by most sops-nix projects

**Note on NUT password**: Reuses `kvmd_admin_password` as the NUT password for simplicity. A dedicated `nut_password` key can be added to `secrets/pikvm.yaml` later if separation is desired. The recipe prints a note about this.

### Change 2: Wire `hosts/common/tailscale.nix`

**Before** (lines 5-7):
```nix
    useRoutingFeatures = "server"; # Enable subnet routing capability
    # Uncomment after setting up sops secrets:
    # authKeyFile = config.sops.secrets.tailscale-auth-key.path;
```

**After** (lines 5-6):
```nix
    useRoutingFeatures = "server"; # Enable subnet routing capability
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
```

Removes the comment line and uncomments the `authKeyFile` assignment. The comment block about manual `tailscale up` at the bottom (lines 17-19) stays since it documents the subnet route advertisement step.

### Change 3: Fix `modules/nut-server/default.nix`

Two locations need fixing.

**Location 1** (lines 28-31) — `users.upsmon`:
```nix
# Before:
      # Replace with sops secret path after setup:
      # passwordFile = config.sops.secrets.nut-password.path;
      passwordFile = "/run/secrets/nut-password"; # placeholder

# After:
      passwordFile = config.sops.secrets.nut-password.path;
```

**Location 2** (line 41) — `upsmon.monitor`:
```nix
# Before:
        passwordFile = "/run/secrets/nut-password";

# After:
        passwordFile = config.sops.secrets.nut-password.path;
```

### Change 4: Add `secrets.nix` to `flake.nix`

**Before** (lines 57-60):
```nix
            ./hosts/common/base.nix
            ./hosts/common/users.nix
            ./hosts/common/tailscale.nix
            ./hosts/common/networking.nix
```

**After** (lines 57-61):
```nix
            ./hosts/common/base.nix
            ./hosts/common/users.nix
            ./hosts/common/tailscale.nix
            ./hosts/common/networking.nix
            ./hosts/common/secrets.nix
```

### Validation

After all four changes, runs `nix flake check`. If it fails, shows the error and suggests running `just setup-secrets` first (the most common cause of failure is `.sops.yaml` still having the placeholder key).

---

## Phase 3-4: Build & Flash

### `just build-all`

Thin wrapper over existing `build-image`:

```justfile
# Build SD images for all hosts
build-all:
    just build-image serial-console
```

Extends naturally when monitor-node is added.

### `just flash-with-check`

```justfile
# Flash with preflight validation
flash-with-check host device:
    just preflight
    just flash {{host}} {{device}}
```

The existing `flash`, `flash-pikvm`, and `preseed-pikvm` recipes remain completely untouched.

---

## Phase 5: Post-Boot — `just setup-post-boot`

```
1. WAIT for hosts on Tailscale
   - Loop with 5-minute timeout:
     tailscale ping --timeout=3s serial-console
     tailscale ping --timeout=3s pikvm-primary
   - Print progress dots, green check on success

2. SSH connectivity check
   - ssh -o ConnectTimeout=5 -o BatchMode=yes root@serial-console true
   - ssh -o ConnectTimeout=5 -o BatchMode=yes root@pikvm-primary true

3. CAPTURE host age keys via setup-host-keys
   - ssh-keyscan -t ed25519 serial-console | ssh-to-age
   - Display key, confirm

4. UPDATE .sops.yaml with host keys
   - Uncomment "# - &serial_console ..."
   - Replace "age1REPLACE_AFTER_FIRST_BOOT" with real key
   - Uncomment "# - *serial_console" in creation_rules

5. REKEY secrets
   - sops updatekeys secrets/pikvm.yaml

6. RUN discover-serial
   - just discover-serial --remote serial-console
   - Display output
   - Print: "Update hosts/serial-console/default.nix with device IDs above"

7. OPTIONAL: deploy
   - Ask "Ready to deploy? (y/n)"
   - just deploy serial-console
```

### `just setup-host-keys host`

Independently runnable sub-recipe:

```justfile
# Capture host SSH key as age key for sops (Phase 5)
setup-host-keys host:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(just _resolve-host {{host}})
    echo "Scanning SSH host key from ${target}..."
    host_age_key=$(ssh-keyscan -t ed25519 "${target}" 2>/dev/null | ssh-to-age)
    if [ -z "$host_age_key" ]; then
        echo "ERROR: Could not get age key from {{host}}. Is it booted?"
        exit 1
    fi
    echo "Host age key: ${host_age_key}"
    echo ""
    echo "Add this to .sops.yaml under 'keys:':"
    echo "  - &{{host}} ${host_age_key}"
    echo ""
    echo "Then uncomment '- *{{host}}' in creation_rules and run:"
    echo "  just rekey-secrets"
```

---

## Phase 6: Validation — `just validate`

```
1. just preflight (must pass with zero FAILs)
2. just health (existing health-check.sh)
3. Additional checks:
   - sops decrypt test: sops -d --extract '["tailscale_authkey"]' secrets/pikvm.yaml
   - nix flake check
   - Serial port reachability: for port 3001-3016, test TCP connect to serial-console
   - Tailscale routing: tailscale ping both hosts
4. Summary with pass/fail/warn counts
```

---

## `just setup-status`

Read-only progress checklist across all phases. Does NOT modify anything.

### Checks

**Phase 0**: tool presence, age key existence
**Phase 1**: `.sops.yaml` configured, `users.nix` has real keys, `authorized_keys` exists, `pikvm.yaml` encrypted
**Phase 2**: `secrets.nix` exists, `tailscale.nix` wired, `nut-server` wired, `flake.nix` includes `secrets.nix`
**Phase 3-4**: image exists in `images/`
**Phase 5**: host keys in `.sops.yaml`, serial device IDs configured
**Phase 6**: SSH reachability to both hosts

Output format:
```
Phase 0: Prerequisites
  [done]  nix installed
  [done]  sops installed
  [done]  age key exists

Phase 1: Secrets & Identity
  [done]  .sops.yaml configured
  [todo]  users.nix needs SSH keys
  ...
```

---

## Dependency Chain

```
                    just setup
                   /    |    \
                  v     v     v
            preflight  setup-secrets  setup-nix
            (Phase 0)  (Phase 1)      (Phase 2)
                           |               |
                           v               v
                      .sops.yaml      secrets.nix (new)
                      users.nix       tailscale.nix
                      pikvm.yaml      nut-server.nix
                      auth_keys       flake.nix
                           |               |
                           +-------+-------+
                                   |
                                   v
                        build-image serial-console
                                   |
                                   v
                        flash serial-console /dev/sdX
                        flash-pikvm /dev/diskN
                                   |
                                   v
                        [physical: insert SD, power on]
                                   |
                                   v
                           setup-post-boot
                           /       |       \
                          v        v        v
                   wait-ts  setup-host-keys  discover-serial
                                   |
                                   v
                           rekey-secrets
                                   |
                                   v
                        deploy serial-console
                                   |
                                   v
                              validate
```

---

## Error Handling Summary

| Scenario | Response |
|----------|----------|
| Missing required tool | FAIL + exit 1 with install instructions |
| Missing optional tool | WARN, continue |
| Age key file absent | ABORT with exact `age-keygen` command |
| No SSH key found | ABORT; suggest passing path as argument |
| Empty interactive input | ABORT (never proceed with empty secrets) |
| Password mismatch | ABORT immediately |
| File already configured | SKIP with yellow "Skipped" message (idempotent) |
| File has local modifications | Backup to `.setup-backup` before overwriting |
| sops encryption fails | ABORT; .sops.yaml probably not configured |
| `nix flake check` fails | Show error, suggest setup-secrets first, do NOT revert |
| Host unreachable (post-boot) | Retry loop with 5-minute timeout |
| `ssh-to-age` returns empty | ABORT with "is host booted?" message |
| macOS vs Linux `sed -i` | Branch on `uname` (matches existing codebase pattern) |

---

## Implementation Sequence

Execute in this order so each step is testable before the next:

1. **Create `.gitignore`** — prevents accidents during all subsequent work
2. **Add `whois` to devShell** in `flake.nix` — provides `mkpasswd`
3. **Write `hosts/common/secrets.nix`** — static file, does not affect build until imported
4. **Append all new recipes to `justfile`** under new section header
5. Test `just preflight` — should detect tools, report placeholders as WARN
6. Test `just setup-status` — should show all phases as [todo]
7. Test `just setup-secrets` interactively — verify file modifications
8. Test `just setup-nix` — verify Nix wiring, flake check passes
9. Test `just setup` end-to-end from clean git state
10. Test `just setup-status` again — phases 1-2 should show [done]

---

## Justfile Insertion Point

All new recipes go between the `# --- Maintenance ---` section (around line 322) and the `# --- Internal Helpers ---` section (line 378). New section header:

```
# ─── Setup & Bootstrap ──────────────────────────────────────
```

This puts setup recipes in `just --list` output between maintenance and internals, which is a natural reading order.

---

## Recommended Supplementary Changes

### 1. `.gitignore` (new file)

```gitignore
# Build artifacts
images/
result
result-*

# Setup backups
*.setup-backup

# Generated preseed files (contain real SSH keys)
hosts/pikvm-primary/preseed/authorized_keys

# Editor temp files
*.swp
*.swo
*~

# direnv cache
.direnv/
```

### 2. `mkpasswd` in devShell

Add `whois` package (which provides `mkpasswd`) to `flake.nix` devShell `buildInputs`.

### 3. NUT password separation (future follow-up)

Currently reuses `kvmd_admin_password` for NUT. To add a separate NUT password:
- Add `nut_password` key to `secrets/pikvm.yaml`
- Update `hosts/common/secrets.nix` secret declaration `key` field
- Add prompt to `setup-secrets`
