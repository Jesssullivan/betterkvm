# Documentation Index

## Architecture & Design
- [architecture.md](architecture.md) — System design, network topology, software stack
- [tesmart-protocol.md](tesmart-protocol.md) — TESmart binary protocol reference (0xAA 0xBB frame format)

## Architecture Decision Records
- [ADR-001: NanoKVM Evaluation](adr-001-nanokvm-evaluation.md) — Retain PiKVM, NanoKVM-USB as bench tool
- [ADR-002: Serial Console Auth](adr-002-serial-console-auth.md) — Tailscale boundary risk acceptance
- [ADR-003: Build Infrastructure](adr-003-build-infrastructure.md) — Native ARM64 CI runners, deferred GF/lab builders

## Operations
- [runbook-secret-rotation.md](runbook-secret-rotation.md) — Tailscale keys, kvmd creds, age key rotation
- [tailscale-acl-alignment.md](tailscale-acl-alignment.md) — Required Tailscale tags, ACL coverage

## Hardware
- [bom.md](bom.md) — Bill of materials (human-readable)
- [../hardware/bom.yaml](../hardware/bom.yaml) — Bill of materials (machine-parseable)
- [../hardware/schematics/atx-wiring.md](../hardware/schematics/atx-wiring.md) — PiKVM A3 → bumble ATX wiring
- [../hardware/schematics/interconnect.md](../hardware/schematics/interconnect.md) — Lab topology and pinouts

## Repo Management
- [../SUBTREES.md](../SUBTREES.md) — Vendor subtree management (kvmd, ustreamer, os)
- [../AGENTS.md](../AGENTS.md) — Agent/operator repo contract
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — How to contribute
- [../SECURITY.md](../SECURITY.md) — Vulnerability reporting
