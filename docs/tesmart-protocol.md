# TESmart HKS1601A1U Protocol Reference

Binary control protocol used by TESmart 16-port HDMI KVM switches.
Applies to HKS1601A1U and similar models (HKS801-M24, etc.).

## Transport

| Transport | Address | Speed | Notes |
|-----------|---------|-------|-------|
| TCP | `10.0.0.50:5000` (lab default), `192.168.1.10:5000` (factory default) | N/A | Preferred when LAN is up |
| RS232 | DB9 on rear panel | 9600 8N1 | Backup when LAN is down |

RS232 uses a standard null-modem cable or USB-TTL adapter at 3.3V/5V TTL
levels depending on model. Pin 2 = RX, Pin 3 = TX, Pin 5 = GND.

## Binary Frame Format

All commands and responses share the same 6-byte frame:

```
Byte:  0     1     2     3     4     5
       0xAA  0xBB  0x03  CMD   VAL   0xEE
       |--header--|  |    |     |    |--footer--|
                     len  cmd   val
```

- **Header**: `0xAA 0xBB` (fixed)
- **Length**: `0x03` (always 3 — covers CMD + VAL + FOOTER)
- **CMD**: Command byte
- **VAL**: Value byte (interpretation depends on CMD)
- **Footer**: `0xEE` (fixed)

## Commands

### Switch Port (CMD 0x01)

Switch the active KVM input to a specified port.

| Field | Value |
|-------|-------|
| CMD | `0x01` |
| VAL | `0x01` – `0x10` (port 1–16, 1-indexed) |

Example — switch to port 5:
```
TX: AA BB 03 01 05 EE
```

No response frame. The switch changes immediately. Allow ≥200ms between
successive switch commands.

### Buzzer Control (CMD 0x02)

Enable or disable the key-press beeper.

| Field | Value |
|-------|-------|
| CMD | `0x02` |
| VAL | `0x01` = on, `0x00` = off |

Example — disable buzzer:
```
TX: AA BB 03 02 00 EE
```

### LCD Timeout (CMD 0x03)

Set the front-panel LCD auto-off timeout.

| Field | Value |
|-------|-------|
| CMD | `0x03` |
| VAL | `0x00` = always on, `0x0A` = 10s, `0x1E` = 30s |

Example — LCD always on:
```
TX: AA BB 03 03 00 EE
```

### Read Active Port (CMD 0x10)

Query which input port is currently active.

| Field | Value |
|-------|-------|
| CMD | `0x10` |
| VAL | `0x00` (ignored) |

Response:

| Field | Value |
|-------|-------|
| CMD | `0x11` |
| VAL | `0x00` – `0x0F` (port 1–16, **0-indexed**) or `0xFF` (no active) |

Example:
```
TX: AA BB 03 10 00 EE
RX: AA BB 03 11 04 EE   → port 5 is active (0x04 + 1)
```

### Auto-Detect Input (CMD 0x81)

Toggle automatic input detection (switch to newly active source).

| Field | Value |
|-------|-------|
| CMD | `0x81` |
| VAL | `0x01` = on, `0x00` = off |

Example — enable auto-detect:
```
TX: AA BB 03 81 01 EE
```

## ASCII Network Configuration

The TCP interface also accepts ASCII queries for reading network settings.
Send the query string followed by `\r\n`. The switch responds with a
single-line ASCII answer.

| Query | Response Example | Description |
|-------|-----------------|-------------|
| `IP?` | `10.0.0.50` | Current IP address |
| `PT?` | `5000` | TCP control port |
| `GW?` | `192.168.1.1` | Default gateway |
| `MA?` | `AA:BB:CC:DD:EE:FF` | MAC address |

These queries are only available over TCP, not RS232.

## Rate Limiting

- Allow ≥200ms between successive binary commands
- The switch may drop commands if flooded
- The `get` (CMD 0x10) response may take up to 500ms
- Retry up to 3 times with 1s backoff on timeout

## RS232 Pinout (DB9 DCE)

| Pin | Signal | Direction |
|-----|--------|-----------|
| 2 | RXD | Switch ← Host |
| 3 | TXD | Switch → Host |
| 5 | GND | Common |

All other pins are not connected. Use a straight-through cable to a
USB-to-RS232 adapter, or a USB-TTL adapter wired directly to pins 2/3/5.

Settings: **9600 baud, 8 data bits, no parity, 1 stop bit (8N1)**.
