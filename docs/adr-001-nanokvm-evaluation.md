# ADR-001: NanoKVM Evaluation — PiKVM vs Sipeed NanoKVM

- **Status**: Accepted
- **Date**: 2026-04-24
- **Context**: TIN-513
- **Decision**: Retain PiKVM A3 as primary centralized KVM; adopt NanoKVM-USB as bench tool only

## Context

BetterKVM runs a TESmart HKS1601A1U 16-port HDMI+USB KVM switch with a PiKVM A3 (Geekworm HAT on Raspberry Pi 4B) in a centralized model — one PiKVM controls all 16 ports through the TESmart switch via TCP:5000 and RS232 DB9.

Sipeed offers multiple NanoKVM products at lower price points. We evaluated whether any NanoKVM variant should replace or supplement the PiKVM.

## Product Line

| Product | Type | Network | Price | Remote-capable |
|---------|------|---------|-------|----------------|
| NanoKVM-USB | USB dongle | None | ~$40 | **No** |
| NanoKVM Cube Full | Standalone IP-KVM (RISC-V SG2002) | 100Mbps | ~$50 | Yes |
| NanoKVM PCIe | Internal PCIe card | 100Mbps | ~$40 | Yes |
| NanoKVM Pro ATX | Enhanced standalone | 1Gbps + WiFi 6 | $79-109 | Yes |
| NanoKVM Pro Desk | Desktop w/ touchscreen | 1Gbps + WiFi 6 | $99-119 | Yes |
| PiKVM A3 (current) | DIY IP-KVM on Pi 4 | 1Gbps | ~$153 | Yes |

**Critical**: NanoKVM-USB is NOT an IP-KVM. It requires a host computer with Chrome/Chromium. It has no network stack and cannot be accessed remotely.

## Decision

**Retain PiKVM A3 as the primary centralized KVM. Adopt NanoKVM-USB as an optional bench/debug tool only.**

No NanoKVM variant replaces PiKVM in the current architecture.

## Rationale

### 1. TESmart Integration (Decisive Factor)

PiKVM has a documented, tested TESmart plugin with GPIO dropdown port switching, TCP:5000 binary protocol control, and RS232 fallback. NanoKVM has **no TESmart support** and users report encoding corruption and HID recognition failures through KVM switches ([NanoKVM #303](https://github.com/sipeed/NanoKVM/issues/303)).

### 2. Security Posture

| Concern | NanoKVM Cube/Pro | PiKVM A3 |
|---------|------------------|----------|
| Phone-home behavior | Downloads `.so` files from Sipeed servers after transmitting device serial | **None** |
| Undocumented hardware | Undocumented microphone found by researchers | None reported |
| CVEs | CVE-2026-32296 (unauth WiFi config, CVSS 5.4); historical hardcoded root:root SSH | No known CVEs |
| Closed-source blobs | Yes — some `.so` binaries remain closed | **Fully open source** |
| Default credentials | Shipped with root:root, admin:admin (historical) | Forced password change on setup |
| Firmware signing | No — key stored plaintext, no integrity checks | No formal signing, but read-only rootfs |

Sources: [Eclypsium audit (Mar 2026)](https://eclypsium.com/blog/your-kvm-is-the-weak-link-how-30-dollar-devices-can-own-your-entire-network/), [CGI Coffee deep-dive (Feb 2025)](https://cgicoffee.com/blog/2025/02/nanokvm-security-issues-consider-pikvm-instead)

### 3. API Maturity

PiKVM's REST/WebSocket API is [documented](https://docs.pikvm.org/api/), supports IPMI/Redfish, has Prometheus metrics, and is battle-tested for automation. NanoKVM's API is reverse-engineered and less mature.

### 4. Cost Analysis

| Approach | Per-port cost | Total (16 ports) |
|----------|--------------|------------------|
| PiKVM A3 + TESmart (current, centralized) | $31.44 | **$503** |
| NanoKVM Cube Full (one per host, distributed) | $50 | $800 |
| NanoKVM Pro ATX (one per host, distributed) | $89 | $1,424 |

Centralized PiKVM is the cheapest option for 16 ports and the only one with proven TESmart integration.

### 5. Architecture Comparison

**Centralized (current PiKVM + TESmart)**:
- Single point of management, one Tailscale node
- Can only view one machine at a time (switch latency ~200ms)
- Single point of failure (mitigated by RS232 fallback)

**Distributed (NanoKVM per host)**:
- Simultaneous multi-machine view
- 16 Ethernet ports, 16 Tailscale nodes, 16 units to manage/update/secure
- Security surface multiplied 16x with a product that has known vulnerabilities

## Where NanoKVM-USB Fits

NanoKVM-USB at $40 is a useful **bench tool** for local debugging:
- Plug into a machine's USB + HDMI, use laptop Chrome to see display
- Completely airgapped — zero network attack surface
- Good for RISC-V boards or machines too awkward to route through the TESmart
- Not a remote access solution; requires physical proximity

## Feature Matrix (Key Dimensions)

| Feature | NanoKVM-USB | NanoKVM Cube/Pro | PiKVM A3 |
|---------|-------------|------------------|----------|
| Video capture | 4K@30 MJPEG | 1080p@60 H.264 | 1080p@50 H.264 |
| HID emulation | Yes (WebSerial) | Yes (USB OTG) | Yes (USB OTG) |
| ATX power control | No | Yes (Pro ATX) | Yes (GPIO) |
| Serial console | No | UART (TTL) | Via USB adapter |
| Ethernet | **None** | 100Mbps / 1Gbps | 1Gbps |
| Tailscale | N/A | Yes | Yes |
| REST API | None | Yes (underdocumented) | Yes (comprehensive) |
| TESmart switch control | N/A | **No support** | **Yes (native plugin)** |
| Open source | Host app only | Partial (closed blobs) | **Fully open** |
| Mobile web UI | No (Chrome desktop only) | Yes | Yes |
| IPMI/Redfish | No | Partial | Yes |

## Consequences

- Continue investing in PiKVM ecosystem (kvmd, ustreamer vendor subtrees)
- Optionally purchase 1-2 NanoKVM-USB dongles for bench debugging
- Do not add NanoKVM Cube/Pro to the lab infrastructure without re-evaluation of their security posture
- If per-port dedicated KVM is needed in the future, prefer PiKVM V4 Mini over NanoKVM (when available) due to security and integration maturity
- Re-evaluate if NanoKVM resolves TESmart compatibility and closes security gaps (track upstream issues)

## References

- [PiKVM TESmart Integration](https://github.com/pikvm/pikvm/blob/master/docs/tesmart.md)
- [PiKVM API Docs](https://docs.pikvm.org/api/)
- [NanoKVM GitHub](https://github.com/sipeed/NanoKVM)
- [NanoKVM-USB GitHub](https://github.com/sipeed/NanoKVM-USB)
- [Eclypsium KVM Vulnerability Research (2026)](https://eclypsium.com/blog/your-kvm-is-the-weak-link-how-30-dollar-devices-can-own-your-entire-network/)
- [NanoKVM Security Deep-Dive (CGI Coffee)](https://cgicoffee.com/blog/2025/02/nanokvm-security-issues-consider-pikvm-instead)
- [Tailscale PiKVM Integration](https://tailscale.com/kb/1292/pikvm)
