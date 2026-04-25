# AGENTS.md

This repository is `betterkvm`, the Tinyland multiarch KVM lab infrastructure project. It manages two Raspberry Pi 4B hosts, a TESmart HKS1601A1U 16-port KVM switch, and remote access to 13+ lab machines via PiKVM, serial consoles, and Tailscale mesh networking.

## Start Here

Before making changes:

1. Run `git status --short --branch`.
2. Run `just --list` and prefer existing recipes over ad hoc shell commands.
3. Read the specific host config, module, or preseed script for the area you are changing before trusting summary docs.

## Source Of Truth

When docs disagree, prefer sources in this order:

1. `justfile`
2. `hosts/pikvm-primary/kvmd/override.yaml` and `hosts/pikvm-primary/preseed/`
3. `hosts/serial-console/default.nix` and `hosts/common/*.nix`
4. `modules/ser2net/default.nix` and `modules/nut-server/default.nix`
5. `packages/tesmart-ctl/tesmart_ctl.py`
6. `docs/architecture.md`

Treat `README.txt` and `docs/bom.md` as orientation only.

## Instruction Resolution

For agent and harness behavior in this repo, use this precedence:

1. Repo-root `AGENTS.md`
2. The nearest in-repo tool overlay between the current working directory and repo root
3. Repo-tracked follow-on docs explicitly named here
4. Home-managed harness bootstrap/default files only after repo-local truth is clear

In practice:

- `CLAUDE.md` is a thin overlay, not the primary operational truth.
- Ignore sibling repos under `~/git` unless the task explicitly asks for cross-repo work.
- The `lab` (crush-dots) repo defines the house style for Nix, justfile, and testing patterns. When aligning conventions, reference `lab` as the authority.

## Architecture

- **Pi #1 (pikvm-primary)**: PiKVM OS (Arch Linux), preseed-bootstrapped, captures HDMI and controls HID via TESmart switch. Not NixOS-managed.
- **Pi #2 (serial-console)**: NixOS, 16-port ser2net serial console aggregation, NUT UPS monitoring, Tailscale subnet router for lab LAN (10.0.0.0/24).
- **TESmart HKS1601A1U**: 16-port HDMI+USB KVM switch, TCP:5000 and RS232 DB9 control interfaces. Binary protocol documented in `docs/tesmart-protocol.md`.
- **Secrets**: sops-nix with age encryption. User age key + host SSH-derived age keys.
- **Vendor code**: `vendor/kvmd`, `vendor/ustreamer`, `vendor/os` are read-only git subtrees. See `SUBTREES.md`.
- **Build**: Nix flake outputs — nixosConfigurations, SD images, tesmart-ctl package. Cross-compiled aarch64-linux from x86_64.

## Hard Rules

- Do not commit secrets, `.env`, or plaintext credentials.
- Do not modify vendor subtrees directly. Use `just subtree-update` for upstream pulls.
- Do not deploy without verifying host reachability first (`just status` or `just health`).
- Prefer `just check` (dry-run) before `just deploy` when the blast radius is unclear.
- Do not treat the PiKVM host as NixOS. It runs Arch Linux and is configured via preseed scripts, not Nix modules.

## Preferred Commands

Use these as the default safe entrypoints:

- `just status`
- `just health`
- `just lint`
- `just check`
- `just build-image serial-console`
- `just deploy serial-console`
- `just switch-port <n>`
- `just serial <hostname>`

If a documented command conflicts with `just --list`, trust `just --list`.

## High-Risk Operations

These require explicit intent and careful review:

- `just flash <host> <device>` — writes to physical media
- `just preseed-pikvm <device>` — injects secrets to boot partition
- `just deploy-pikvm` — pushes config to live PiKVM
- `just rekey-secrets` — re-encrypts all sops secrets
- any operation touching `secrets/pikvm.yaml`

## Machine Mapping

| Port | Hostname | Arch | Notes |
|------|----------|------|-------|
| 1 | honey | x86_64 | |
| 2 | bumble | x86_64 | ATX power control |
| 3 | petting-zoo-mini | aarch64 | |
| 4 | xoxd-bates | aarch64 | |
| 5 | yoga | x86_64 | |
| 6 | mbp-13 | x86_64 | |
| 7 | betsy | — | |
| 8 | musey | RISC-V | |
| 9 | sdr-1 | — | |
| 10 | g2-1 | aarch64 | |
| 11 | g2-2 | aarch64 | |
| 12 | t-deck | aarch64 | |
| 13 | tdeck-pro | aarch64 | |
| 14–16 | (unassigned) | — | Spare |

## Tracker Hygiene

- Use `TIN-*` issue references in PR titles or bodies.
- BetterKVM workstreams are tracked under the Linear project "BetterKVM" (TIN-507 through TIN-513).
- If a PR has no Linear issue, use `Linear: none` in the PR body and explain why.

## What To Read For Current Work

- [AGENTS.md](AGENTS.md) — this file
- [docs/architecture.md](docs/architecture.md)
- [docs/tesmart-protocol.md](docs/tesmart-protocol.md)
- [docs/bom.md](docs/bom.md)
- [hardware/schematics/interconnect.md](hardware/schematics/interconnect.md)
- [SUBTREES.md](SUBTREES.md)
