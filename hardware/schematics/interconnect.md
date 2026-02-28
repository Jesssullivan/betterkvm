# Lab Interconnect Diagram

## Physical Topology

```
                          ┌──────────────────────┐
                          │   Tailscale VPN       │
                          │   (WireGuard mesh)    │
                          └──────────┬───────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
               ┌────┴────┐    ┌─────┴─────┐    Remote Devs
               │ Pi #1   │    │ Pi #2     │    (laptops)
               │ PiKVM   │    │ NixOS     │
               │ A3 HAT  │    │ serial-   │
               │         │    │ console   │
               └────┬────┘    └─────┬─────┘
                    │               │
    ┌───────────────┼───────────────┼──────────────────┐
    │           Lab LAN (10.0.0.0/24)                  │
    │               │               │                  │
    │          ┌────┴────┐    ┌─────┴─────┐            │
    │          │ TESmart │    │ Smart PDU │            │
    │          │HKS1601  │    │ (NUT)     │            │
    │          │ A1U     │    └───────────┘            │
    │          │ 16-port │                             │
    │          └────┬────┘                             │
    └───────────────┼──────────────────────────────────┘
                    │
    ┌───────────────┼───────────────────────────────────────────────┐
    │               │  HDMI + USB (per port)                       │
    │  ┌────────────┼──────────────────────────────────────────┐   │
    │  │  Port  1: honey           Port  9: sdr-1             │   │
    │  │  Port  2: bumble (ATX)    Port 10: g2-1              │   │
    │  │  Port  3: petting-zoo     Port 11: g2-2              │   │
    │  │  Port  4: xoxd-bates      Port 12: t-deck            │   │
    │  │  Port  5: yoga            Port 13: tdeck-pro          │   │
    │  │  Port  6: mbp-13          Port 14: (unassigned)       │   │
    │  │  Port  7: betsy           Port 15: (unassigned)       │   │
    │  │  Port  8: musey           Port 16: (unassigned)       │   │
    │  └───────────────────────────────────────────────────────┘   │
    │                         Lab Machines                         │
    └──────────────────────────────────────────────────────────────┘
```

## Pi #1: PiKVM A3 Connections

| Interface | Destination | Cable | Purpose |
|-----------|-------------|-------|---------|
| CSI (HDMI capture) | TESmart HDMI out | HDMI 1ft | Video capture from active port |
| USB-C OTG | TESmart USB input | USB-A to USB-C | HID keyboard/mouse to active port |
| Ethernet | Lab LAN switch | Cat6 1ft | TCP control of TESmart (port 5000) |
| GPIO (ATX header) | X630-A5 RJ45 | RJ45 Cat5e | ATX power/reset for bumble |
| Tailscale | WireGuard mesh | (virtual) | Remote web UI access |

## Pi #2: NixOS Serial Console Connections

| Interface | Destination | Cable | Purpose |
|-----------|-------------|-------|---------|
| Ethernet | Lab LAN switch | Cat6 1ft | Subnet router for 10.0.0.0/24 |
| USB (Gearmo 4-port) | Lab machines UART | USB-TTL | Serial consoles (ser2net) |
| USB (additional) | Lab machines UART | USB-TTL | Serial consoles (ser2net) |
| USB | UPS | USB-A | NUT UPS monitoring |
| Tailscale | WireGuard mesh | (virtual) | Subnet routing + SSH |

## RS232 Backup Control Path

```
Pi #2 USB-TTL ──RS232──> TESmart DB9 (rear panel)
                          9600 8N1
                          Same binary protocol as TCP
```

Fallback when the TESmart LAN interface is unreachable. Use:
```bash
tesmart-ctl --serial /dev/ttyUSB0 get
tesmart-ctl --serial /dev/ttyUSB0 set 5
```

## TESmart HKS1601A1U Rear Panel

```
┌─────────────────────────────────────────────────────────────┐
│  [HDMI OUT]  [USB-B]  [RJ45 LAN]  [DB9 RS232]  [DC 12V]   │
│                                                             │
│  [1] [2] [3] [4] [5] [6] [7] [8]  ← HDMI IN (top row)     │
│  [9] [10][11][12][13][14][15][16]  ← HDMI IN (bottom row)  │
│                                                             │
│  [1] [2] [3] [4] [5] [6] [7] [8]  ← USB IN (top row)      │
│  [9] [10][11][12][13][14][15][16]  ← USB IN (bottom row)   │
└─────────────────────────────────────────────────────────────┘
```
