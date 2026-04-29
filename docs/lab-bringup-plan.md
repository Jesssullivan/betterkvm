# Lab Bring-Up Plan

This is the operator plan for turning the BetterKVM repo plus hardware into a
running, reproducible lab. It is intentionally staged so each phase leaves clear
evidence before the next higher-risk step.

## User Story

An operator with the repository, the listed hardware, and Tinyland admin access
can:

- Verify the bill of materials and physical wiring without tribal knowledge.
- Flash both Raspberry Pis from repo-managed commands.
- Enroll the Pis into Tailscale with the intended tags and subnet route.
- Bring up KVM video/HID, TESmart switching, serial consoles, UPS/NUT, and ATX
  power control.
- Validate the lab end to end and know which artifacts prove it works.
- Rebuild or rotate credentials later without exposing plaintext secrets.

## Current Truth

- Repo setup through secrets and Nix wiring is already mostly complete:
  `just preflight` passes locally.
- The devices have not been flashed or brought online yet.
- The serial-console image is not currently built locally.
- Post-boot facts are still unknown: serial adapter IDs, host age keys, live
  Tailscale state, TESmart reachable address, WOL MAC addresses, and PDU/UPS
  attachment.
- The latest observed GitHub CI run before bring-up tooling repair had a red
  `Build SD Image` job due an aarch64 execution/binfmt problem.
- GloriousFlywheel/Jess overlay can accelerate x86_64 validation via shared
  Attic/Bazel cache hints, but it does not currently provide a native
  `aarch64-linux` image-builder lane. SD image generation uses
  `ubuntu-24.04-arm` until that exists.
- A local `just build-image serial-console` attempt on the Darwin workstation
  reached Nix build planning, fetched public cache paths, then stopped because
  the configured builders are `x86_64-linux` and `aarch64-darwin`, not
  `aarch64-linux`.
- `just health` and `just validate` have been repaired locally so they can
  report offline hardware cleanly; live hardware validation is still pending.
- `just lint` has been scoped to repo Nix source roots so local `.direnv`
  caches do not mask project warnings.
- Network truth has been converged on TESmart control at `10.0.0.50:5000`.
  `192.168.1.10` remains documented only as the factory default/fallback before
  the switch is re-addressed.

## Tracker Alignment

As of 2026-04-29, the Linear project `BetterKVM` is active. The live bring-up
work is tracked by `TIN-743` and split into hardware-gated follow-ups:

| Issue | Status | Scope |
|-------|--------|-------|
| `TIN-743` | In Progress | Umbrella for lab bring-up |
| `TIN-746` | In Progress | Produce the serial-console SD image artifact on a native `aarch64-linux` path |
| `TIN-747` | Todo | Audit BOM and apply cable labels before lab flashing |
| `TIN-748` | Todo | Flash serial-console and PiKVM SD media from repo-managed flows |
| `TIN-749` | Todo | Enroll Pis in Tailscale and capture host age keys |
| `TIN-751` | Todo | Discover serial adapter IDs and map ser2net ports to hardware |
| `TIN-750` | Todo | Run live KVM, serial, UPS, and ATX validation |

Keep repo changes, Linear comments, and bench evidence aligned with these issue
IDs. Do not run destructive flash/preseed recipes until `TIN-746` has a known
image artifact and the operator has confirmed exact SD device paths.

## Definition Of Done

- `docs/bom.md` and `hardware/bom.yaml` match the actual purchased inventory.
- `hardware/schematics/interconnect.md` matches physical cable labels and port
  assignments.
- `just build-image serial-console` produces a bootable image, and CI can build
  or publish the same artifact.
- `just flash serial-console <device>` and `just flash-pikvm <device>` are the
  only required flashing flows.
- `pikvm-primary` and `serial-console` are reachable over Tailscale by hostname.
- `serial-console` advertises and routes `10.0.0.0/24` as intended.
- TESmart TCP control and RS232 backup control both work.
- PiKVM web UI shows all 16 ports and can switch the active port.
- Video and HID work through PiKVM for each connected machine.
- ser2net exposes ports `3001-3016` with correct machine mapping.
- `bumble` ATX power/reset and LED state work from PiKVM.
- NUT reports UPS status from the serial-console Pi.
- WOL buttons use real MAC addresses or are removed for machines that do not
  support WOL.
- `just setup-status`, `just health`, and `just validate` report useful final
  state without hanging or exiting early.
- No plaintext secrets, auth keys, or generated `.env` files are tracked.

## Phase 0: Repo And Tracker Baseline

Goal: make sure the plan starts from known repo/tracker state.

Actions:

- Run `git status --short --branch`.
- Run `just --list` and use recipe names from that output.
- Confirm the current Linear project state for BetterKVM and create follow-up
  issues only for real remaining work.
- Keep the existing untracked `.claude/plans/` note out of commits unless it is
  intentionally promoted into repo docs.

Acceptance:

- Worktree is clean except known local-only files.
- Current branch and remote are understood.
- Remaining work is represented either in this plan or in Linear.

## Phase 1: Fix Bring-Up Tooling Before Hardware

Goal: make status commands trustworthy before plugging in devices.

Required fixes:

- Fix `scripts/health-check.sh` counter increments so `set -e` does not stop the
  script after the first PASS/FAIL/WARN.
- Fix `just validate` so the TESmart TCP probe has a reliable timeout on macOS
  and Linux.
- Fix `just validate` to call the real TESmart CLI command, `tesmart-ctl get`,
  not `tesmart-ctl get-port`.
- Scope `just lint` and `just fmt` to repo Nix source roots so generated caches
  and vendor trees are excluded.
- Decide the CI image-build path:
  native `ubuntu-24.04-arm` for SD image builds.
- Re-run `just test`, `just lint`, and the smallest practical image build proof.

Acceptance:

- `just health` prints all sections even when hardware is offline.
- `just validate` fails quickly and cleanly when hardware is offline.
- CI no longer fails from `Exec format error` in the SD image job.
- Local image builds either run on a real `aarch64-linux` builder or explicitly
  defer to native arm64 CI; Darwin plus the current remote builders is not a
  sufficient image-generation path.

## Phase 2: BOM, Inventory, And Label Plan

Goal: make the lab physically reproducible.

Inventory updates:

- Mark each BOM item as owned, ordered, missing, or substituted.
- Add exact model numbers for serial adapters, PDU/UPS, SD cards, PoE hardware,
  and any USB hubs.
- Record any substitutions in both `docs/bom.md` and `hardware/bom.yaml`.
- Decide how many serial ports are required on day one. The repo maps all 16,
  but the current BOM only explicitly covers a partial adapter set.

Labeling convention:

- KVM HDMI/USB cables: `KVM-P01-honey` through `KVM-P16-spare`.
- Serial cables: `SER-P01-honey` through `SER-P16-spare`.
- Network cables: `NET-pikvm`, `NET-serial`, `NET-tesmart`, `NET-pdu`.
- Power cables/outlets: `PDU-O01-honey` etc. when the PDU is installed.

Acceptance:

- A reader can match every cable label to a port, host, and repo config entry.
- BOM reflects actual hardware on the bench, not only planned purchases.

## Phase 3: Network Truth

Goal: settle IPs, names, tags, and routes before flashing.

Decisions to make and document:

| Component | Proposed Truth | Repo Surfaces |
|-----------|----------------|---------------|
| `pikvm-primary` | DHCP plus Tailscale MagicDNS | `justfile`, PiKVM preseed |
| `serial-console` | DHCP plus Tailscale MagicDNS | NixOS config, deploy-rs |
| TESmart | `10.0.0.50` on lab LAN | `override.yaml`, `tesmart-ctl`, docs |
| PDU/UPS | `10.0.0.51` if networked PDU is used | docs, future NUT config |
| Lab route | `10.0.0.0/24` via `serial-console` | `tailscale.nix`, Tailscale ACL |

Prep:

- Generate or select reusable/ephemeral Tailscale auth keys with the required
  tags from `docs/tailscale-acl-alignment.md`.
- Confirm tag approval behavior in the Tailscale admin console.
- Re-address the TESmart from `192.168.1.10` to `10.0.0.50` before final PiKVM
  validation, or temporarily set `TESMART_HOST=192.168.1.10` during the first
  bench probe.

Acceptance:

- Docs and code agree on the TESmart address.
- Tailscale enrollment commands and tags are known before the first boot.
- DHCP reservations or static IP assignments are recorded.

## Phase 4: Physical Wiring

Goal: wire the lab in a way that can be audited visually.

PiKVM:

- PiKVM A3 HDMI capture input from TESmart HDMI output.
- PiKVM USB OTG/HID to TESmart console USB input.
- PiKVM Ethernet to lab management switch.
- PiKVM ATX RJ45/X630-A5 cable to `bumble` front-panel header.

Serial console:

- Serial-console Ethernet to lab management switch.
- USB serial adapters to target machine UART/serial ports.
- RS232 adapter to TESmart DB9 backup control.
- UPS USB or network path connected and identified.

TESmart:

- HDMI and USB input pairs wired by matching port number.
- Ports 1-13 wired to assigned machines.
- Ports 14-16 labeled spare.
- TESmart LAN connected to management switch.

Acceptance:

- `hardware/schematics/interconnect.md` matches the bench.
- `hardware/schematics/atx-wiring.md` matches the `bumble` motherboard header.
- Each cable can be unplugged and restored by label alone.

## Phase 5: Flashing

Goal: produce boot media using repo-managed flows only.

Serial-console SD:

```bash
just preflight
just build-image serial-console
just flash serial-console <device>
```

PiKVM SD:

```bash
just preflight
just flash-pikvm <device>
```

Safety notes:

- Treat `flash`, `flash-pikvm`, and `preseed-pikvm` as destructive.
- Verify the target device path immediately before each flash.
- Do not run deploy recipes until host reachability is proven.

Acceptance:

- Serial-console SD image path exists under `images/serial-console`.
- PiKVM SD card contains preseed files on the boot partition.
- No plaintext secrets remain on the workstation beyond ignored local files.

## Phase 6: First Boot And Enrollment

Goal: get both Pis reachable and capture post-boot facts.

Serial-console:

- Boot serial-console Pi.
- Confirm it appears in Tailscale.
- Confirm SSH as the intended user.
- Capture SSH host age key and update `.sops.yaml`.
- Run `just rekey-secrets`.

PiKVM:

- Boot PiKVM.
- Confirm root SSH and web UI reachability over Tailscale.
- Confirm first-boot scripts consumed and deleted preseed secrets.
- Confirm `override.yaml` is installed and `kvmd` starts.

Post-boot discovery:

```bash
just setup-post-boot
just discover-serial
```

Acceptance:

- `.sops.yaml` has the serial-console host age key.
- `secrets/pikvm.yaml` can be decrypted by the intended keys.
- `hosts/serial-console/default.nix` no longer contains
  `REPLACE_WITH_ACTUAL_ID`.

## Phase 7: Service Bring-Up

Goal: verify each subsystem independently before declaring the lab live.

Checks:

- `just status`
- `just health`
- `just current-port`
- `just switch-port 1`
- `just serial honey`
- `just nut-status`
- PiKVM web UI login and video stream.
- PiKVM HID input to active machine.
- PiKVM ATX power/reset for `bumble`.
- TESmart RS232 fallback with `tesmart-ctl --serial <device> get`.

Acceptance:

- Every connected machine has at least one verified access path:
  PiKVM video/HID, serial console, SSH, or power control.
- TESmart port state agrees between PiKVM UI and `tesmart-ctl`.
- `just validate` completes without hanging.

## Phase 8: Security Posture

Goal: leave the lab in a maintainable, least-surprise state.

Controls:

- Keep PiKVM as Arch/PiKVM OS, not NixOS.
- Keep NixOS secrets under sops-nix.
- Rotate Tailscale preseed auth keys after successful enrollment.
- Keep generated `authorized_keys`, `.env`, images, and build results ignored.
- Prefer Tailscale-only administrative access.
- Confirm password SSH login is disabled on serial-console.
- Confirm PiKVM web auth is not using a long-lived shared bootstrap password if
  `TIN-537` onetime auth is implemented later.
- Confirm serial console exposure is acceptable under ADR-002.
- Run secret scanning before publishing any bring-up branch.

Acceptance:

- Secret rotation runbook has been followed after initial preseed.
- Tailscale ACL tags match `docs/tailscale-acl-alignment.md`.
- No unexpected services are reachable from outside the tailnet/lab LAN.

## Phase 9: Reproducibility Artifacts

Goal: make the second build easier than the first.

Artifacts to update after hardware truth is known:

- `docs/bom.md` and `hardware/bom.yaml` with final inventory.
- `hardware/schematics/interconnect.md` with final cable map.
- `hardware/schematics/atx-wiring.md` with verified `bumble` header facts.
- `docs/architecture.md` with final IP addressing and route truth.
- `docs/tailscale-acl-alignment.md` if tags or ACL behavior differ.
- `docs/runbook-secret-rotation.md` if preseed rotation differs in practice.
- `hosts/serial-console/default.nix` with real serial device mappings.
- `hosts/pikvm-primary/kvmd/override.yaml` with real WOL MAC addresses or
  removed WOL buttons.

Acceptance:

- A future operator can rebuild from repo docs and commands without reading old
  chat logs or local plan files.

## Proposed Linear Slices

Existing backlog already covers some work:

- `TIN-537`: kvmd onetime auth for safer bootstrap.
- `TIN-538`: verify ustreamer Tailscale MTU behavior on live hardware.
- `TIN-539`: NixOS VM tests for ser2net, NUT, and Tailscale modules.
- `TIN-540`: Renovate for flake and GitHub Actions dependency updates.

Recommended additional slices:

- Bring-up tooling repair: `health`, `validate`, and CI image build.
- Hardware inventory and cable-label finalization.
- Network truth convergence for TESmart, PDU, and subnet routing.
- Flash and first-boot proof for `serial-console`.
- Flash and first-boot proof for `pikvm-primary`.
- Serial adapter discovery and stable udev mapping.
- End-to-end KVM, serial, ATX, NUT, and RS232 validation.
- Security closeout: auth key rotation, host age key rekey, secret scan.
