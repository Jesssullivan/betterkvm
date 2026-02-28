# Architecture

## System Overview

```
Remote Developers
    |
    | Tailscale VPN (WireGuard)
    |
    v
+---+---------------------------+
|   Tailscale Subnet Router     |  Pi #2 (NixOS)
|   serial-console              |  advertises 10.0.0.0/24
+---+---------------------------+
    |
    | Lab Management Network (10.0.0.0/24)
    |
+---+--------+----------+------+----------+
|            |          |      |          |
v            v          v      v          v
Pi #1        TESmart    Gearmo Smart     Lab
(PiKVM)      HKS1601A1U 16-port PDU     Machines
             KVM Switch Serial (NUT)     (16 ports)
             16-port    Hub
```

## Machine-to-Port Mapping

| Port | Hostname | Notes |
|------|----------|-------|
| 1 | honey | |
| 2 | bumble | ATX via X630-A5 RJ45 |
| 3 | petting-zoo-mini | |
| 4 | xoxd-bates | |
| 5 | yoga | |
| 6 | mbp-13 | |
| 7 | betsy | |
| 8 | musey | |
| 9 | sdr-1 | |
| 10 | g2-1 | |
| 11 | g2-2 | |
| 12 | t-deck | |
| 13 | tdeck-pro | |
| 14-16 | (unassigned) | |

## Pi Roles

### Pi #1: PiKVM (KVM-over-IP)
- **OS**: Stock PiKVM OS (Arch Linux ARM, read-only rootfs)
- **Hardware**: Raspberry Pi 4 2GB + Geekworm KVM-A3 HAT ($153 total)
- **Software**: kvmd, ustreamer, nginx, Tailscale
- **Network**: HDMI capture from TESmart output, USB HID to TESmart USB
- **Config**: `/etc/kvmd/override.yaml` (deployed via `just deploy-pikvm`)
- **Preseed**: Zero-touch first boot via `just preseed-pikvm` (passwords, SSH keys, Tailscale, override.yaml)
- **ATX Control**: GPIO 24/25/21/20 → X630-A5 RJ45 → bumble front-panel header
- **WoL**: Wake-on-LAN for honey, bumble, xoxd-bates, betsy, musey
- **Why not NixOS**: kvmd is not in nixpkgs; PiKVM OS is an appliance

### Pi #2: Serial Console + Subnet Router + NUT
- **OS**: NixOS (full declarative, managed via flake)
- **Hardware**: Raspberry Pi 4 2GB + Gearmo 4-port FTDI + USB-TTL adapters
- **Software**: ser2net, Tailscale (subnet router), NUT (UPS monitor)
- **Network**: USB serial adapters to each lab machine's UART/RS-232
- **Config**: Nix flake (`just deploy serial-console`)
- **Serial Consoles**: 16 ports (TCP 3001-3016) mapped to lab machines
- **RS232 Backup**: USB-TTL to TESmart DB9 for switch control when LAN is down

## Network Topology

```
Internet
    |
[Tailscale DERP / P2P]
    |
    +-- Developer laptops (Tailscale clients)
    |
    +-- Pi #2: serial-console (Tailscale subnet router)
    |       |-- eth0: DHCP on lab LAN
    |       |-- tailscale0: routes 10.0.0.0/24 to tailnet
    |       |-- USB: serial adapters (ser2net ports 3001-3016)
    |       |-- USB: UPS (NUT usbhid-ups driver)
    |       |-- USB-TTL: RS232 backup to TESmart DB9
    |
    +-- Pi #1: pikvm-primary (Tailscale node)
    |       |-- eth0: DHCP on lab LAN
    |       |-- CSI: HDMI capture from TESmart
    |       |-- USB-C OTG: HID to TESmart USB input
    |       |-- TCP:5000 -> TESmart switch control (16 ports)
    |       |-- GPIO: ATX power/reset to bumble (via X630-A5)
    |
Lab LAN (10.0.0.0/24)
    |
    +-- TESmart HKS1601A1U (10.0.0.50)
    |       HDMI+USB to 16 lab machines
    |       RS232 DB9 backup control (9600 8N1)
    |
    +-- Smart PDU (10.0.0.51, SNMP for NUT)
    |       per-outlet power control
    |
    +-- Lab machines (10.0.0.100-115)
            HDMI -> TESmart (16 ports)
            USB -> TESmart (16 ports)
            UART -> Pi #2 serial adapters
```

## Software Stack

### PiKVM (Pi #1)
```
nginx (TLS) -> kvmd (Python asyncio) -> ustreamer (C, video)
                  |-> HID plugin (USB OTG keyboard/mouse)
                  |-> ATX plugin (GPIO power control for bumble)
                  |-> uGPIO/TESmart plugin (TCP:5000 switch control, 16 ports)
                  |-> WoL plugin (magic packets for selected machines)
                  |-> MSD plugin (virtual USB drive)
```

### Serial Console (Pi #2)
```
NixOS
  |-> ser2net (TCP 3001-3016 -> /dev/serial/*)
  |-> tailscale (subnet router, advertises 10.0.0.0/24)
  |-> NUT upsd (monitors UPS via USB, serves status on TCP:3493)
  |-> udev rules (persistent /dev/serial/* symlinks)
```

### TESmart Control
```
tesmart-ctl (Python CLI)
  |-> TCP transport (192.168.1.10:5000, default)
  |-> RS232 serial transport (--serial /dev/ttyUSB0, backup)
  |-> Commands: get, set, buzzer, lcd, autodetect, info, monitor
  |-> Protocol: 0xAA 0xBB 0x03 CMD VAL 0xEE (see docs/tesmart-protocol.md)
```

## Deployment Workflow

### Initial Setup (Zero-Touch)
1. `just build-image serial-console` — Build NixOS SD image on x86_64
2. `just flash serial-console /dev/sdX` — Flash to SD card with dd
3. Boot Pi #2, it auto-joins Tailscale
4. `just flash-pikvm /dev/diskN` — Download PiKVM OS, flash, and preseed
5. Boot Pi #1 — preseed scripts configure passwords, SSH, Tailscale, override.yaml
6. PiKVM web UI shows 16 ports, ATX controls for bumble, WoL buttons

### Preseed Flow
```
just flash-pikvm /dev/diskN
  |-> Download stock PiKVM image
  |-> Flash with flash-sd.sh
  |-> just preseed-pikvm /dev/diskN
        |-> Mount boot partition
        |-> Copy pikvm.txt, pikvm-scripts.d/*, override.yaml, authorized_keys
        |-> Decrypt secrets (sops) -> pikvm-secrets/
        |-> Unmount
```

On first boot, PiKVM runs `pikvm-scripts.d/01-05`:
1. Set root + kvmd passwords (from decrypted secrets, then delete)
2. Install SSH authorized_keys
3. Install override.yaml
4. Authenticate Tailscale (from decrypted auth key, then delete)
5. Set hostname, trigger reboot

### Ongoing Updates
- NixOS Pi: `just deploy serial-console` (deploy-rs with rollback)
- PiKVM Pi: `just deploy-pikvm` (scp override.yaml + restart kvmd)
- Flake updates: `just update && just deploy-all`

## Secrets Management

- **sops-nix** with age encryption for NixOS secrets
- Encrypted secrets committed to git (`secrets/*.yaml`)
- Decrypted at NixOS activation via SSH host key → age key derivation
- PiKVM secrets in `secrets/pikvm.yaml` (sops-encrypted)
- Flash-time injection: `just preseed-pikvm` decrypts and writes to SD boot partition
- First-boot scripts consume secrets and delete plaintext files

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| PiKVM OS vs NixOS for KVM | PiKVM OS | kvmd not in nixpkgs, works OOB |
| NixOS for serial Pi | NixOS | ser2net/tailscale/NUT all in nixpkgs |
| Pi 4 vs Pi 5 | Pi 4 for both | Pi 5 lacks GPU H.264 encoder (PiKVM), Pi 4 cheaper |
| Geekworm A3 vs official V4 | Geekworm A3 | $153 vs $385, same PiKVM OS |
| TESmart HKS1601A1U vs HKS801-M24 | HKS1601A1U (16-port) | Supports full lab (13 machines + 3 spare) |
| deploy-rs vs colmena | deploy-rs | Reuses flake nixosConfigurations, auto rollback |
| ser2net vs conserver | ser2net | In nixpkgs, YAML config, simpler |
| DIY vs pre-built | DIY KVM + NixOS serial | Best cost/flexibility balance |
| TCP vs RS232 for TESmart | Both | TCP primary, RS232 backup when LAN is down |
| Manual PiKVM vs preseed | Preseed | Zero-touch SD flashing with preseeded auth |
