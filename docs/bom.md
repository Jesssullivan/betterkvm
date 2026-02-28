# Bill of Materials

## Phase 1: Core KVM + Serial Console (~$600)

| # | Item | Qty | Price | Total | Source |
|---|------|-----|-------|-------|--------|
| 1 | Raspberry Pi 4 Model B 2GB | 2 | $55 | $110 | [raspberrypi.com](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) |
| 2 | Geekworm KVM-A3 HAT (PiKVM) | 1 | $80 | $80 | [geekworm.com](https://geekworm.com/products/pikvm-a3) |
| 3 | TESmart HKS1601A1U (16-port KVM) | 1 | $350 | $350 | [tesmart.com](https://www.tesmart.com) |
| 4 | Samsung EVO Plus 64GB SD | 1 | $10 | $10 | Amazon |
| 5 | Samsung PRO Endurance 128GB SD | 1 | $18 | $18 | Amazon |
| 6 | Cat6 patch cables 1ft (5-pack) | 1 | $10 | $10 | Amazon |
| 7 | HDMI cable (1ft, for KVM capture) | 1 | $7 | $7 | Amazon |
| 8 | Velcro cable ties (50-pack) | 1 | $7 | $7 | Amazon |
| | | | | **$592** | |

## Phase 2: Serial Console + Power (~$275)

| # | Item | Qty | Price | Total | Source |
|---|------|-----|-------|-------|--------|
| 9 | Gearmo 4-port FTDI USB Serial | 1 | $70 | $70 | [Amazon](https://www.amazon.com/Gearmo-Serial-Windows-Certified-Drivers/dp/B004ETDC8K) |
| 10 | DTECH FTDI 3.3V USB-TTL adapters | 4 | $10 | $40 | [Amazon](https://us.amazon.com/DTECH-Adapter-Compatible-Windows-Genuine/dp/B0D97W4YDL) |
| 11 | USB-RS232 adapter (TESmart backup) | 1 | $15 | $15 | Amazon |
| 12 | Used APC AP7900 PDU (8-outlet) | 1 | $150 | $150 | eBay |
| | | | | **$275** | |

## Phase 3: ATX + Networking Polish (~$145)

| # | Item | Qty | Price | Total | Source |
|---|------|-----|-------|-------|--------|
| 13 | Geekworm X630-A5 RJ45-ATX cable | 1 | $10 | $10 | [geekworm.com](https://geekworm.com) |
| 14 | PoE+ HAT for Pi | 2 | $20 | $40 | [raspberrypi.com](https://www.raspberrypi.com/products/poe-plus-hat/) |
| 15 | TP-Link TL-SG108PE PoE switch | 1 | $70 | $70 | [Amazon](https://www.amazon.com/TP-Link-TL-SG108PE/) |
| 16 | Cable labels (Brother TZe tape) | 1 | $15 | $15 | Amazon |
| 17 | 1U rack shelf (3D print) | 1 | $5 | $5 | [Printables #69176](https://www.printables.com/model/69176) |
| | | | | **$140** | |

## Optional / Future

| Item | Price | Notes |
|------|-------|-------|
| HDMI EDID emulator dongles (16x) | $80 | Backup if HKS1601A1U EDID fails ($5 each) |
| USB Ethernet adapter (2nd NIC) | $15 | If VLANs insufficient for mgmt net |
| Raspberry Pi 5 4GB (dev Pi) | $85 | Optional 3rd Pi for monitoring |
| Digi CM16 (used, 16-port serial) | $150 | Enterprise serial console upgrade |
| Additional USB-TTL adapters | $40 | For remaining serial ports (4x $10) |

## Grand Total

| Phase | Cost |
|-------|------|
| Phase 1: Core KVM (16-port) | ~$592 |
| Phase 2: Serial + Power | ~$275 |
| Phase 3: ATX + Networking | ~$140 |
| **Total (all phases)** | **~$1,007** |

## Cost Comparison vs Pre-Built

| Approach | Total |
|----------|-------|
| **This DIY build (16-port)** | ~$1,007 |
| PiKVM V4 Plus + TESmart 16-port + ser2net Pi | ~$1,400 |
| Savings | **~$393 (28%)** |

## Vendor Quick Links

- PiKVM products: https://pikvm.org/buy/
- PiKVM OS images: https://pikvm.org/download/
- TESmart store: https://www.tesmart.com
- Geekworm KVM: https://geekworm.com/collections/pikvm
- BliKVM (alternative): https://www.blikvm.com
- Printables (rack mounts): https://www.printables.com/model/69176
