# Contributing to BetterKVM

## Quick Start

1. Enter the dev shell: `nix develop` or `direnv allow`
2. Read `AGENTS.md` for the repo contract and source-of-truth hierarchy
3. Run `just --list` to see available recipes
4. Run `just test` before submitting changes

## Development Workflow

```bash
just lint          # statix, deadnix
just fmt           # nixfmt-rfc-style
just test          # Hypothesis PBT suite
just check         # nix flake check
just status        # lab node status (needs Tailscale)
```

## Commit Messages

Use conventional commits: `type(scope): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Include `TIN-*` Linear issue references in the commit body when applicable.

## Testing

All changes to `packages/tesmart-ctl/`, `mcp/`, or `hosts/` should include or update PBT tests in `tests/pbt/`. Run `just test-verbose` to see individual test results.

## Nix Changes

- Format with `nixfmt-rfc-style` (enforced by CI)
- Lint with `statix` and `deadnix` (enforced by CI)
- Do not modify files under `vendor/` — use `just subtree-update` for upstream pulls

## PiKVM vs NixOS

Pi #1 (pikvm-primary) runs Arch Linux, not NixOS. Configuration goes in `hosts/pikvm-primary/preseed/` and `hosts/pikvm-primary/kvmd/`. Do not generate Nix modules for it.

Pi #2 (serial-console) runs NixOS. Configuration is declarative in `hosts/serial-console/default.nix` and the shared modules under `hosts/common/`.

## Secrets

Never commit plaintext secrets. Use `sops` for encrypted secrets in `secrets/`. See `docs/runbook-secret-rotation.md` for rotation procedures.
