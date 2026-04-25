# Secret Rotation Runbook

Procedures for rotating secrets managed by sops-nix in the BetterKVM lab.

## Prerequisites

- `sops`, `age`, `ssh-to-age` available (in `nix develop` devShell)
- User age key at `~/.config/sops/age/keys.txt`
- Access to running Pi hosts via SSH

## Tailscale Auth Key Rotation

Tailscale authkeys should be rotated when:
- Suspected compromise of SD card or boot partition
- Key has been reusable for >90 days
- After any preseed operation

### Procedure

1. Generate new key in Tailscale admin console (admin.tailscale.com):
   - Settings → Keys → Generate auth key
   - Select: **Ephemeral** (preferred) or **Reusable** (if Pi needs reconnection)
   - Set expiry: 90 days max

2. Update sops secret:
   ```
   just edit-secret pikvm.yaml
   # Change tailscale_authkey value
   ```

3. If PiKVM is already running, SSH in and update:
   ```
   just ssh pikvm-primary
   tailscale logout
   tailscale up --authkey="<new-key>" --hostname=pikvm-primary
   ```

4. Verify: `just tailscale-status`

## kvmd Admin Credential Rotation

### Procedure

1. Generate a new random credential:
   ```
   pwgen -s 24 1  # generates a random string
   ```

2. Generate hash for sops:
   ```
   mkpasswd -m sha-512 '<new-password>'
   ```

3. Update sops secrets:
   ```
   just edit-secret pikvm.yaml
   # Update kvmd_admin_password (plaintext, for kvmd-htpasswd)
   # Update pikvm_root_password_hash (SHA-512 hash, for usermod)
   ```

4. Apply to running PiKVM:
   ```
   just ssh pikvm-primary
   kvmd-htpasswd set admin '<new-password>'
   usermod -p '<hash>' root
   ```

## Age Key Rotation

### User Key

1. Generate new age key:
   ```
   age-keygen -o ~/.config/sops/age/keys.txt.new
   ```

2. Update `.sops.yaml` with new public key

3. Re-encrypt all secrets:
   ```
   just rekey-secrets
   ```

4. Move new key into place:
   ```
   mv ~/.config/sops/age/keys.txt.new ~/.config/sops/age/keys.txt
   ```

### Host Key (after Pi rebuild)

1. Get host SSH public key:
   ```
   ssh-keyscan serial-console 2>/dev/null | ssh-to-age
   ```

2. Update `.sops.yaml` with new host age key

3. Re-encrypt:
   ```
   just rekey-secrets
   ```

4. Redeploy:
   ```
   just deploy serial-console
   ```

## Recovery: Lost Age Key

If the user age key is lost:

1. If any host still has a valid age key (derived from SSH host key):
   - SSH to that host
   - Decrypt secrets using the host's key
   - Generate new user key and re-encrypt

2. If all keys are lost:
   - Secrets in `secrets/pikvm.yaml` are unrecoverable
   - Re-create all secrets from scratch:
     - New Tailscale authkey from admin console
     - New kvmd password (generate + hash)
     - New root password hash
   - Update `.sops.yaml` with new key(s)
   - Run `just setup-secrets` to bootstrap fresh

## Rotation Schedule

| Secret | Rotation | Trigger |
|--------|----------|---------|
| Tailscale authkey | Every 90 days or on compromise | Calendar reminder or preseed |
| kvmd admin password | Every 180 days | Calendar reminder |
| Root password hash | Every 180 days | With kvmd password |
| User age key | Annually or on compromise | Calendar reminder |
| Host age keys | On Pi rebuild only | `just setup-post-boot` |
