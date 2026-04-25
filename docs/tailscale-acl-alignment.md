# Tailscale ACL Alignment

How betterkvm hosts map to the lab's Tailscale ACL policy (`policy.hujson` in crush-dots).

## Required Tags

| Host | Tags | Purpose |
|------|------|---------|
| serial-console | `tag:tinyland-lab-common`, `tag:subnet-router` | SSH access, subnet routing for 10.0.0.0/24 |
| pikvm-primary | `tag:tinyland-lab-common`, `tag:dev` | SSH access, KVM web UI access |

## ACL Coverage

### Serial Console Access (ports 3001-3016)

Serial consoles are reachable by:
- `group:dollhouse-admins` → `tag:tinyland-lab-common:*` (full port access)
- `tag:dev` → `tag:dev:*` (dev-to-dev, all ports)

Since serial-console is tagged `tag:tinyland-lab-common`, admin users and `tag:dev` devices can reach ports 3001-3016 for ser2net telnet access.

### KVM Web UI (port 443)

PiKVM kvmd web UI on pikvm-primary:
- `group:dollhouse-admins` → `tag:dev:*` (full access)
- `group:dollhouse-users` → `tag:dev:*` (via developer group)

### Subnet Routing (10.0.0.0/24)

The serial-console Pi advertises `10.0.0.0/24` as a subnet route:
- `autoApprovers.routes["10.0.0.0/8"]` includes `tag:subnet-router`
- Auto-approved — no manual admin action needed

### SSH Access

Both Pis accessible via SSH:
- `group:dollhouse-admins` → `tag:tinyland-lab-common` as root, jess, jsullivan2

## No ACL Changes Needed

The existing lab ACL policy covers all betterkvm access patterns. The only requirement is correct tagging when enrolling the Pis via `tailscale up`:

```bash
# serial-console
tailscale up --advertise-tags=tag:tinyland-lab-common,tag:subnet-router \
  --advertise-routes=10.0.0.0/24

# pikvm-primary
tailscale up --advertise-tags=tag:tinyland-lab-common,tag:dev
```

Note: Tag assignment requires admin approval in Tailscale admin console unless using auth keys with pre-approved tags.
