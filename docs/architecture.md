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
(PiKVM)      HKS801-M24 8-port PDU      Machines
             KVM Switch Serial (NUT)
             8-port     Hub
```

## Pi Roles

### Pi #1: PiKVM (KVM-over-IP)
- **OS**: Stock PiKVM OS (Arch Linux ARM, read-only rootfs)
- **Hardware**: Raspberry Pi 4 2GB + Geekworm KVM-A3 HAT ($153 total)
- **Software**: kvmd, ustreamer, nginx, Tailscale
- **Network**: HDMI capture from TESmart output, USB HID to TESmart USB
- **Config**: `/etc/kvmd/override.yaml` (deployed via `just deploy-pikvm`)
- **Why not NixOS**: kvmd is not in nixpkgs; PiKVM OS is an appliance

### Pi #2: Serial Console + Subnet Router + NUT
- **OS**: NixOS (full declarative, managed via flake)
- **Hardware**: Raspberry Pi 4 2GB + Gearmo 4-port FTDI + USB-TTL adapters
- **Software**: ser2net, Tailscale (subnet router), NUT (UPS monitor)
- **Network**: USB serial adapters to each lab machine's UART/RS-232
- **Config**: Nix flake (`just deploy serial-console`)

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
    |       |-- USB: serial adapters (ser2net ports 3001-3008)
    |       |-- USB: UPS (NUT usbhid-ups driver)
    |
    +-- Pi #1: pikvm-primary (Tailscale node)
    |       |-- eth0: DHCP on lab LAN
    |       |-- CSI: HDMI capture from TESmart
    |       |-- USB-C OTG: HID to TESmart USB input
    |       |-- TCP:5000 -> TESmart switch control
    |
Lab LAN (10.0.0.0/24)
    |
    +-- TESmart HKS801-M24 (10.0.0.50)
    |       HDMI+USB to 8 lab machines
    |
    +-- Smart PDU (10.0.0.51, SNMP for NUT)
    |       per-outlet power control
    |
    +-- Lab machines (10.0.0.100-107)
            HDMI -> TESmart
            USB -> TESmart
            UART -> Pi #2 serial adapters
```

## Software Stack

### PiKVM (Pi #1)
```
nginx (TLS) -> kvmd (Python asyncio) -> ustreamer (C, video)
                  |-> HID plugin (USB OTG keyboard/mouse)
                  |-> ATX plugin (GPIO power control)
                  |-> uGPIO/TESmart plugin (TCP:5000 switch control)
                  |-> MSD plugin (virtual USB drive)
```

### Serial Console (Pi #2)
```
NixOS
  |-> ser2net (TCP 3001-3008 -> /dev/serial/*)
  |-> tailscale (subnet router, advertises 10.0.0.0/24)
  |-> NUT upsd (monitors UPS via USB, serves status on TCP:3493)
  |-> udev rules (persistent /dev/serial/* symlinks)
```

## Deployment Workflow

### Initial Setup
1. `just build-image serial-console` -- Build NixOS SD image on x86_64 (Yoga)
2. `just flash serial-console /dev/sdX` -- Flash to SD card with dd
3. Boot Pi #2, it auto-joins Tailscale
4. `just flash-pikvm /dev/sdX` -- Flash PiKVM OS to separate SD card
5. Boot Pi #1, configure via PiKVM web UI
6. `just deploy-pikvm` -- Push TESmart override.yaml

### Ongoing Updates
- NixOS Pi: `just deploy serial-console` (deploy-rs with rollback)
- PiKVM Pi: `just deploy-pikvm` (scp override.yaml + restart kvmd)
- Flake updates: `just update && just deploy-all`

## Secrets Management

- **sops-nix** with age encryption for NixOS secrets
- Encrypted secrets committed to git (`secrets/*.yaml`)
- Decrypted at NixOS activation via SSH host key -> age key derivation
- PiKVM secrets managed manually (Tailscale auth, kvmd passwords)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| PiKVM OS vs NixOS for KVM | PiKVM OS | kvmd not in nixpkgs, works OOB |
| NixOS for serial Pi | NixOS | ser2net/tailscale/NUT all in nixpkgs |
| Pi 4 vs Pi 5 | Pi 4 for both | Pi 5 lacks GPU H.264 encoder (PiKVM), Pi 4 cheaper |
| Geekworm A3 vs official V4 | Geekworm A3 | $153 vs $385, same PiKVM OS |
| deploy-rs vs colmena | deploy-rs | Reuses flake nixosConfigurations, auto rollback |
| ser2net vs conserver | ser2net | In nixpkgs, YAML config, simpler |
| DIY vs pre-built | DIY KVM + NixOS serial | Best cost/flexibility balance |
