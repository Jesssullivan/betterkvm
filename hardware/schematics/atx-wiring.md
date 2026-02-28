# ATX Wiring: PiKVM A3 → bumble

## Overview

The PiKVM A3 (Geekworm KVM-A3 HAT) provides ATX power control via an
RJ45 jack that connects to the target machine's front-panel header.
In this lab, the ATX connection goes to **bumble** (port 2) via the
Geekworm X630-A5 RJ45-to-ATX breakout cable.

## RJ45 Pinout (T-568B)

| RJ45 Pin | Color (568B) | Signal | ATX Header Pin | Direction |
|----------|-------------|--------|----------------|-----------|
| 1 | Orange/White | Power LED+ | Pin 2 (PLED+) | Machine → PiKVM |
| 2 | Orange | HDD LED+ | Pin 1 (HDDLED+) | Machine → PiKVM |
| 3 | Green/White | Power SW | Pin 6 (PWRSW) | PiKVM → Machine |
| 4 | Blue | GND | Pin 5 (GND) | Common |
| 5 | Blue/White | GND | Pin 7 (GND) | Common |
| 6 | Green | Reset SW | Pin 8 (RSTSW) | PiKVM → Machine |
| 7 | Brown/White | HDD LED- | Pin 3 (HDDLED-) | Machine → PiKVM |
| 8 | Brown | Power LED- | Pin 4 (PLED-) | Machine → PiKVM |

## PiKVM V3/A3 GPIO Mapping

The Geekworm A3 HAT uses the standard PiKVM V3 GPIO assignments:

| GPIO | Function | Direction | Active |
|------|----------|-----------|--------|
| 24 | Power Switch | Output | Low pulse |
| 25 | Reset Switch | Output | Low pulse |
| 21 | Power LED | Input | High = ON |
| 20 | HDD LED | Input | High = activity |

These are the V3 defaults in kvmd. No override.yaml changes needed for
ATX — the default `__atx_power__`, `__atx_reset__`, and `__atx_power_led__`
GPIO mappings are correct out of the box.

## X630-A5 Breakout Cable

The Geekworm X630-A5 is an RJ45-to-dupont breakout cable:

```
RJ45 plug ──Cat5e──> X630-A5 breakout ──dupont──> Motherboard F_PANEL header
(PiKVM A3)            (splitter board)              (bumble)
```

### Motherboard Front-Panel Header (2x5, 2.54mm)

Standard Intel front-panel connector pinout:

```
          ┌─────────────┐
HDDLED+ ──┤ 1         2 ├── PLED+
HDDLED- ──┤ 3         4 ├── PLED-
  GND   ──┤ 5         6 ├── PWRSW
  GND   ──┤ 7         8 ├── RSTSW
  KEY   ──┤ 9        10 ├── (NC)
          └─────────────┘
```

## Wiring Verification

After connecting, verify in the PiKVM web UI:
1. Power LED indicator should reflect machine power state
2. Power button should toggle machine on/off (2s press)
3. Reset button should trigger machine reset
4. Force-off should work (6s hold via web UI)
