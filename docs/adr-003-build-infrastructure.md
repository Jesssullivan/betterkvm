# ADR-003: Build Infrastructure — Runner and Cache Strategy

- **Status**: Accepted
- **Date**: 2026-04-24
- **Context**: TIN-509
- **Decision**: Use GloriousFlywheel `tinyland-nix` runners with cluster-local Attic and Bazel caches; cross-compile aarch64-linux via QEMU on x86_64 runners with warm cache

## Context

BetterKVM builds NixOS SD card images targeting `aarch64-linux` (Raspberry Pi 4B). The current CI uses QEMU emulation on x86_64 GitHub runners (`ubuntu-latest`), which is extremely slow (timeout set at 180 minutes).

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

### Immediate
1. **All CI jobs on `tinyland-nix` GloriousFlywheel runners** — cluster-local access to Attic and Bazel caches
2. **Cross-compile aarch64-linux SD images via QEMU on x86_64 runners** — with warm Attic cache, QEMU cross-compile is fast (cached derivations skip compilation)
3. **`ensure-nix` composite action** — bootstraps Nix, sets `ATTIC_SERVER` and `BAZEL_REMOTE_CACHE` env vars from cluster DNS
4. **Attic cache at `http://attic.nix-cache.svc.cluster.local`** — cluster-internal, no Tailscale dependency in CI

### Medium term
- Deploy aarch64 ARC runner pool in GloriousFlywheel for native ARM builds
- Wire Bazel remote cache for tesmart-ctl and MCP server builds
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
build-image:
  runs-on: tinyland-nix
  steps:
    - uses: ./.github/actions/ensure-nix
    # Cluster-local Attic at http://attic.nix-cache.svc.cluster.local
    # QEMU cross-compile with cached derivations = fast
```

## Consequences

- Build times drop from ~60-180 min to ~5-15 min (estimated 10-22x improvement)
- No dependency on GloriousFlywheel or lab infrastructure for CI
- Free for public repos; within free minutes for private repos
- QEMU and docker/setup-qemu-action removed from CI (simpler pipeline)
- RISC-V CI path available via RISE when needed
- Attic cache continues to provide warm builds when on Tailscale

## References

- [GitHub ARM64 runners GA](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/)
- [ARM64 in private repos](https://github.blog/changelog/2026-01-29-arm64-standard-runners-are-now-available-in-private-repositories/)
- [Actuated: native ARM 22x faster](https://actuated.com/blog/native-arm64-for-github-actions)
- [RISE RISC-V runners](https://riseproject.dev/2026/03/24/announcing-the-rise-risc-v-runners-free-native-risc-v-ci-on-github/)
- [DeterminateSystems nix-installer](https://github.com/DeterminateSystems/nix-installer-action)
