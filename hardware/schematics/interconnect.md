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

| Interface | Destination | Cable Label | Cable | Purpose |
|-----------|-------------|-------------|-------|---------|
| CSI (HDMI capture) | TESmart HDMI out | `VID-tesmart-out-pikvm` | HDMI 1ft | Video capture from active port |
| USB-C OTG | TESmart USB console input | `USB-tesmart-console-pikvm` | USB-A to USB-C | HID keyboard/mouse to active port |
| Ethernet | Lab LAN switch | `NET-pikvm` | Cat6 1ft | TCP control of TESmart (port 5000) |
| GPIO (ATX header) | X630-A5 RJ45 | `ATX-bumble-pikvm` | RJ45 Cat5e | ATX power/reset for bumble |
| Tailscale | WireGuard mesh | virtual | virtual | Remote web UI access |

## Pi #2: NixOS Serial Console Connections

| Interface | Destination | Cable Label | Cable | Purpose |
|-----------|-------------|-------------|-------|---------|
| Ethernet | Lab LAN switch | `NET-serial` | Cat6 1ft | Subnet router for 10.0.0.0/24 |
| USB (Gearmo 4-port) | Lab machines UART | `SER-P01`-`SER-P04` | USB-TTL | Serial consoles (ser2net) |
| USB (additional) | Lab machines UART | `SER-P05`-`SER-P16` | USB-TTL | Serial consoles (ser2net) |
| USB | UPS | `USB-ups-serial` | USB-A | NUT UPS monitoring |
| USB-RS232 | TESmart DB9 | `SER-tesmart-rs232` | USB-RS232 | TESmart backup control |
| Tailscale | WireGuard mesh | virtual | virtual | Subnet routing + SSH |

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

## Network Labels

| Label | Endpoint A | Endpoint B | Address Truth |
|-------|------------|------------|---------------|
| `NET-pikvm` | PiKVM Ethernet | Lab LAN switch | DHCP plus Tailscale MagicDNS |
| `NET-serial` | Serial-console Ethernet | Lab LAN switch | DHCP plus Tailscale MagicDNS; routes 10.0.0.0/24 |
| `NET-tesmart` | TESmart RJ45 LAN | Lab LAN switch | Static or reserved `10.0.0.50` |
| `NET-pdu` | Smart PDU Ethernet | Lab LAN switch | Static or reserved `10.0.0.51` when installed |

## Port Cable Label Manifest

Each TESmart port gets matching HDMI, USB, serial, and optional power labels.
Ports 14-16 are labeled even when unused so spare wiring stays reproducible.

| Port | Hostname | HDMI Label | USB Label | Serial Label | Power Label |
|------|----------|------------|-----------|--------------|-------------|
| 1 | honey | `KVM-P01-honey-HDMI` | `KVM-P01-honey-USB` | `SER-P01-honey` | `PDU-O01-honey` |
| 2 | bumble | `KVM-P02-bumble-HDMI` | `KVM-P02-bumble-USB` | `SER-P02-bumble` | `PDU-O02-bumble` |
| 3 | petting-zoo-mini | `KVM-P03-petting-zoo-mini-HDMI` | `KVM-P03-petting-zoo-mini-USB` | `SER-P03-petting-zoo-mini` | `PDU-O03-petting-zoo-mini` |
| 4 | xoxd-bates | `KVM-P04-xoxd-bates-HDMI` | `KVM-P04-xoxd-bates-USB` | `SER-P04-xoxd-bates` | `PDU-O04-xoxd-bates` |
| 5 | yoga | `KVM-P05-yoga-HDMI` | `KVM-P05-yoga-USB` | `SER-P05-yoga` | `PDU-O05-yoga` |
| 6 | mbp-13 | `KVM-P06-mbp-13-HDMI` | `KVM-P06-mbp-13-USB` | `SER-P06-mbp-13` | `PDU-O06-mbp-13` |
| 7 | betsy | `KVM-P07-betsy-HDMI` | `KVM-P07-betsy-USB` | `SER-P07-betsy` | `PDU-O07-betsy` |
| 8 | musey | `KVM-P08-musey-HDMI` | `KVM-P08-musey-USB` | `SER-P08-musey` | `PDU-O08-musey` |
| 9 | sdr-1 | `KVM-P09-sdr-1-HDMI` | `KVM-P09-sdr-1-USB` | `SER-P09-sdr-1` | `PDU-O09-sdr-1` |
| 10 | g2-1 | `KVM-P10-g2-1-HDMI` | `KVM-P10-g2-1-USB` | `SER-P10-g2-1` | `PDU-O10-g2-1` |
| 11 | g2-2 | `KVM-P11-g2-2-HDMI` | `KVM-P11-g2-2-USB` | `SER-P11-g2-2` | `PDU-O11-g2-2` |
| 12 | t-deck | `KVM-P12-t-deck-HDMI` | `KVM-P12-t-deck-USB` | `SER-P12-t-deck` | `PDU-O12-t-deck` |
| 13 | tdeck-pro | `KVM-P13-tdeck-pro-HDMI` | `KVM-P13-tdeck-pro-USB` | `SER-P13-tdeck-pro` | `PDU-O13-tdeck-pro` |
| 14 | spare | `KVM-P14-spare-HDMI` | `KVM-P14-spare-USB` | `SER-P14-spare` | `PDU-O14-spare` |
| 15 | spare | `KVM-P15-spare-HDMI` | `KVM-P15-spare-USB` | `SER-P15-spare` | `PDU-O15-spare` |
| 16 | spare | `KVM-P16-spare-HDMI` | `KVM-P16-spare-USB` | `SER-P16-spare` | `PDU-O16-spare` |

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
