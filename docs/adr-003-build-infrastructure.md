# ADR-003: Build Infrastructure — Runner and Cache Strategy

- **Status**: Accepted
- **Date**: 2026-04-24
- **Context**: TIN-509
- **Decision**: Use GloriousFlywheel `tinyland-nix` runners for x86_64 validation with cluster-local Attic/Bazel cache hints; build aarch64-linux SD images on native GitHub-hosted `ubuntu-24.04-arm` until a native GloriousFlywheel arm64 lane exists

## Context

BetterKVM builds NixOS SD card images targeting `aarch64-linux` (Raspberry Pi
4B). The original CI plan used QEMU emulation on x86_64 runners, which was slow
and later failed on the `tinyland-nix` lane when binfmt could not execute
aarch64 builders.

Three alternatives were evaluated:
1. GloriousFlywheel private ARC runners
2. Lab Nix remote builders (honey, xoxd-bates, petting-zoo-mini)
3. GitHub public ARM64 runners

## Investigation Findings

### GloriousFlywheel (Private Runners)

**Actual state** (not aspirational):
- All ARC scale sets are **x86_64 only**: `tinyland-nix`, `tinyland-docker`, `tinyland-dind`
- No aarch64 runner images, no ARM64 ARC scale sets, no multi-arch Docker builds
- RISC-V support: "not started" — demand-shaped, not product-shaped
- aarch64-darwin works locally on M1 Macs (repo-scoped proof only)
- Bazel aarch64 platform configs are **commented out**

**Verdict**: Cannot serve betterkvm's aarch64-linux needs today. Defer until GF deploys ARM runner pools.

### Lab Nix Remote Builders

| Builder | System | Status | Can build aarch64-linux? |
|---------|--------|--------|--------------------------|
| honey | x86_64-linux | Online (Tailscale) | Only via QEMU/binfmt (same speed problem) |
| xoxd-bates | aarch64-darwin | Online (Tailscale) | **No** — darwin only |
| petting-zoo-mini | aarch64-darwin | Online (Tailscale) | **No** — linux-builder disabled (Determinate Nix conflict) |

- SSH key materialized at `~/.ssh/nix-remote-builder` (SOPS-backed, verified)
- All builders reachable via Tailscale
- Auth recently verified in AI Lab Parity Sprint (2026-04-24)

**Verdict**: No builder can natively produce aarch64-linux. honey can cross-compile but it's still QEMU under the hood. Not a speedup.

### GitHub Public ARM64 Runners

| Feature | Detail |
|---------|--------|
| Label | `ubuntu-24.04-arm` |
| Status | GA since Aug 2025 |
| Pricing (public repos) | **Free** |
| Pricing (private repos) | Same rate as x64 (within free minutes since Jan 2026) |
| Specs | 4 vCPU (Arm Neoverse), ~14 GB disk |
| Nix support | DeterminateSystems/nix-installer-action works natively |
| Performance vs QEMU | **10-22x faster** |
| RISC-V | RISE RISC-V runners available (Early Availability, free for OSS) |

**Verdict**: Clear winner for immediate needs. Drop-in replacement, dramatically faster, free.

## Decision

### Amendment: 2026-04-29

The `Build SD Image` and release image jobs now run on GitHub-hosted
`ubuntu-24.04-arm` runners. GitHub's hosted runner reference lists this as a
Linux arm64 label, and the previous `tinyland-nix` QEMU path failed with
`Exec format error` because binfmt was not actually able to execute aarch64
builders. Keep `tinyland-nix` for fast x86_64 lint, package, and PBT jobs; use
native arm64 where the output is an aarch64 NixOS SD image.

The adjacent GloriousFlywheel/Jess overlay state confirms the same boundary:
`jesssullivan-infra` exposes capability-shaped lanes such as `tinyland-nix`,
`tinyland-nix-heavy`, `tinyland-nix-kvm`, and `tinyland-nix-gpu`, plus the shared
Attic and Bazel cache endpoints. It does not provide a native `aarch64-linux`
image-builder lane for BetterKVM today, and BetterKVM should not introduce a
repo-specific runner label to get one. Current proof is shared-cache attachment
for x86_64 validation and local Bazel execution, not full remote build offload.

### Immediate
1. **x86_64 validation jobs on `tinyland-nix` GloriousFlywheel runners** — cluster-local access to Attic and Bazel caches
2. **aarch64-linux SD image jobs on GitHub-hosted `ubuntu-24.04-arm` runners** — native execution avoids QEMU/binfmt fragility
3. **`ensure-nix` composite action** — bootstraps Nix, sets `ATTIC_SERVER` and `BAZEL_REMOTE_CACHE` env vars from cluster DNS
4. **Attic cache at `http://attic.nix-cache.svc.cluster.local`** — cluster-internal, used by `tinyland-nix` jobs

### Medium term
- Deploy aarch64 ARC runner pool in GloriousFlywheel for native ARM builds
- Wire Bazel shared-cache proof for tesmart-ctl and MCP server builds if/when
  BetterKVM adopts a Bazel surface; the current repo is Nix/Python-only
- Evaluate RISE RISC-V runners for `musey` (RISC-V board) testing

### Future
- Native aarch64-linux runner pool for SD image builds (eliminates QEMU overhead)
- Restore petting-zoo-mini linux-builder when Determinate Nix compatibility is resolved

## CI Workflow Changes

### Before (public GH runners, cold cache, ~120min+)
```yaml
build-image:
  runs-on: ubuntu-latest  # or ubuntu-24.04-arm
  # No Attic access, every derivation from source
```

### After (GF runners, warm Attic cache, ~10-20 min estimated)
```yaml
lint:
  runs-on: tinyland-nix

build-image:
  runs-on: ubuntu-24.04-arm
  steps:
    - uses: ./.github/actions/ensure-nix
    - run: nix build .#images.serial-console --print-build-logs
```

## Consequences

- Build times drop from ~60-180 min to ~5-15 min (estimated 10-22x improvement)
- SD image builds no longer depend on GloriousFlywheel or lab infrastructure
- Free for public repos; within free minutes for private repos
- QEMU and docker/setup-qemu-action removed from CI (simpler pipeline)
- RISC-V CI path available via RISE when needed
- Attic and Bazel cache hints continue to attach x86_64 jobs to the shared
  GloriousFlywheel substrate where the runner can resolve cluster-local DNS

## References

- [GitHub-hosted runners reference](https://docs.github.com/actions/reference/runners/github-hosted-runners)
- [GitHub ARM64 runners GA](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/)
- [ARM64 in private repos](https://github.blog/changelog/2026-01-29-arm64-standard-runners-are-now-available-in-private-repositories/)
- [Actuated: native ARM 22x faster](https://actuated.com/blog/native-arm64-for-github-actions)
- [RISE RISC-V runners](https://riseproject.dev/2026/03/24/announcing-the-rise-risc-v-runners-free-native-risc-v-ci-on-github/)
- [DeterminateSystems nix-installer](https://github.com/DeterminateSystems/nix-installer-action)
