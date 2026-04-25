# ADR-002: Serial Console Authentication Model

- **Status**: Accepted
- **Date**: 2026-04-24
- **Context**: TIN-511 (security hardening)
- **Decision**: Accept unauthenticated serial consoles behind Tailscale boundary with documented risk

## Context

The serial-console Pi exposes 16 ser2net TCP ports (3001-3016) for telnet access to lab machine serial consoles. These ports have no authentication — anyone who can reach the TCP port can interact with the serial device.

Current network topology:
```
Internet → [Tailscale DERP] → serial-console Pi → ser2net (ports 3001-3016) → USB serial → lab machines
                                    ↑
                              Lab LAN (10.0.0.0/24) — also reachable via Tailscale subnet routing
```

## Options Evaluated

### Option A: Add ser2net authentication
- ser2net supports `authdir` with username/password files
- Adds auth prompt before serial access
- **Downside**: Breaks `just serial <host>` ergonomics, complicates automation, passwords to manage
- **Downside**: ser2net auth is plaintext telnet — not real security, just obfuscation

### Option B: SSH tunneled serial access
- Replace direct TCP telnet with SSH port forwarding
- `ssh -L 3001:localhost:3001 serial-console` then `telnet localhost 3001`
- **Upside**: SSH key auth, encrypted transport
- **Downside**: Extra hop, harder to script, doesn't protect against local LAN access

### Option C: Tailscale ACL boundary (current + formalized)
- Serial ports only reachable via Tailscale mesh or lab LAN
- Tailscale ACLs restrict which nodes can reach serial-console
- NixOS firewall restricts which interfaces ser2net binds to
- **Upside**: Zero-friction access for authorized Tailscale users
- **Downside**: Anyone on the lab LAN segment can access serial consoles

### Option D: Bind ser2net to Tailscale interface only
- Modify ser2net to bind only on `tailscale0` interface, not `0.0.0.0`
- Lab LAN access blocked; only Tailscale-authenticated users can connect
- **Upside**: Strong auth boundary (Tailscale device auth)
- **Downside**: Can't access serial consoles from lab LAN directly (e.g., from another Pi)

## Decision

**Accept Option C (Tailscale ACL boundary) with Option D as a future hardening step.**

Serial consoles are inherently low-security interfaces — they transmit plaintext over UART. Adding telnet-level auth creates security theater without meaningful protection. The real boundary is Tailscale device authentication.

### Immediate actions
1. Document that serial consoles are unauthenticated TCP telnet
2. Ensure serial-console Pi is only reachable via Tailscale (not exposed to untrusted networks)
3. Align with lab repo's `policy.hujson` Tailscale ACLs

### Future hardening (Option D)
1. Bind ser2net to `tailscale0` interface only (removes lab LAN attack surface)
2. Add Tailscale ACL tag `tag:serial-access` for fine-grained access control

## Risk Acceptance

| Risk | Severity | Mitigation | Residual |
|------|----------|-----------|----------|
| Unauthorized serial access via Tailscale | Low | Tailscale device auth + ACLs | Trusted users only |
| Unauthorized serial access via lab LAN | Medium | Physical lab access required | Accept: lab is physically secured |
| Serial session hijacking | Low | ser2net `kickolduser: true` | Single-user per port |
| Credential exposure via serial output | Medium | Training: don't type passwords in serial sessions | Accept: operator responsibility |

## Consequences

- No ser2net auth configuration needed (keeps module simple)
- Serial access works seamlessly via `just serial <hostname>`
- Documented risk acceptance satisfies TIN-511 security audit requirement
- Future PR can add `tailscale0` binding without breaking the module interface
