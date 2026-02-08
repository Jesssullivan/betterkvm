#!/usr/bin/env python3
"""tesmart-ctl: CLI for TESmart KVM switch control over TCP.

Usage:
    tesmart-ctl get                     Query active port
    tesmart-ctl set <port>              Switch to port (1-based)
    tesmart-ctl buzzer <on|off>         Control buzzer
    tesmart-ctl lcd <0|10|30>           LCD timeout in seconds
    tesmart-ctl monitor                 Continuously poll and display port

Protocol: 0xAA 0xBB 0x03 <cmd> <val> 0xEE over TCP (default 192.168.1.10:5000)

Environment:
    TESMART_HOST  (default: 192.168.1.10)
    TESMART_PORT  (default: 5000)
"""

import argparse
import os
import socket
import sys
import time

HEADER = bytes([0xAA, 0xBB, 0x03])
FOOTER = bytes([0xEE])

CMD_SWITCH = 0x01
CMD_BUZZER = 0x02
CMD_LCD = 0x03
CMD_READ = 0x10
CMD_AUTODET = 0x81
RESP_PORT = 0x11

DEFAULT_HOST = os.environ.get("TESMART_HOST", "192.168.1.10")
DEFAULT_PORT = int(os.environ.get("TESMART_PORT", "5000"))
TIMEOUT = 3.0
RETRY_COUNT = 3
RETRY_DELAY = 1.0


def build_command(cmd: int, value: int) -> bytes:
    return HEADER + bytes([cmd, value]) + FOOTER


def send_command(host: str, port: int, cmd: int, value: int,
                 expect_response: bool = False) -> bytes | None:
    frame = build_command(cmd, value)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(TIMEOUT)
        sock.connect((host, port))
        sock.sendall(frame)
        if expect_response:
            time.sleep(0.2)
            data = sock.recv(64)
            return data
    return None


def parse_port_response(data: bytes) -> int | None:
    if not data or len(data) < 6:
        return None
    idx = data.find(bytes([0xAA, 0xBB, 0x03, RESP_PORT]))
    if idx == -1:
        return None
    port_val = data[idx + 4]
    if port_val == 0xFF:
        return None
    return port_val + 1  # 0-indexed to 1-indexed


def cmd_get(args):
    for attempt in range(RETRY_COUNT):
        try:
            resp = send_command(args.host, args.port, CMD_READ, 0x00,
                                expect_response=True)
            port = parse_port_response(resp)
            if port is not None:
                print(f"Active port: {port}")
                return 0
        except (socket.timeout, ConnectionRefusedError, OSError) as e:
            if attempt == RETRY_COUNT - 1:
                print(f"ERROR: {e}", file=sys.stderr)
        if attempt < RETRY_COUNT - 1:
            time.sleep(RETRY_DELAY)
    print("ERROR: Could not read active port", file=sys.stderr)
    return 1


def cmd_set(args):
    target = int(args.target)
    if not (1 <= target <= 16):
        print("ERROR: Port must be 1-16", file=sys.stderr)
        return 1
    try:
        send_command(args.host, args.port, CMD_SWITCH, target)
        print(f"Switched to port {target}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_buzzer(args):
    val = 1 if args.state in ("on", "1") else 0
    try:
        send_command(args.host, args.port, CMD_BUZZER, val)
        print(f"Buzzer {'on' if val else 'off'}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_lcd(args):
    mapping = {"0": 0x00, "10": 0x0A, "30": 0x1E}
    val = mapping.get(args.seconds)
    if val is None:
        print("ERROR: LCD timeout must be 0, 10, or 30", file=sys.stderr)
        return 1
    try:
        send_command(args.host, args.port, CMD_LCD, val)
        label = "never" if args.seconds == "0" else f"{args.seconds}s"
        print(f"LCD timeout: {label}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_monitor(args):
    print("Monitoring TESmart switch (Ctrl+C to stop)...")
    last_port = None
    while True:
        try:
            resp = send_command(args.host, args.port, CMD_READ, 0x00,
                                expect_response=True)
            port = parse_port_response(resp)
            if port != last_port:
                print(f"[{time.strftime('%H:%M:%S')}] Port changed: {last_port} -> {port}")
                last_port = port
        except (socket.timeout, ConnectionRefusedError, OSError):
            print(f"[{time.strftime('%H:%M:%S')}] Connection failed")
        time.sleep(2)


def main():
    parser = argparse.ArgumentParser(
        description="TESmart KVM switch control",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--host", default=DEFAULT_HOST,
                        help=f"Switch IP (default: {DEFAULT_HOST}, env: TESMART_HOST)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"Switch TCP port (default: {DEFAULT_PORT}, env: TESMART_PORT)")

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("get", help="Query active port")

    p_set = sub.add_parser("set", help="Switch to port N")
    p_set.add_argument("target", help="Port number (1-16)")

    p_buzz = sub.add_parser("buzzer", help="Control buzzer")
    p_buzz.add_argument("state", choices=["on", "off", "0", "1"])

    p_lcd = sub.add_parser("lcd", help="Set LCD timeout")
    p_lcd.add_argument("seconds", choices=["0", "10", "30"])

    sub.add_parser("monitor", help="Continuously poll port changes")

    args = parser.parse_args()
    handlers = {
        "get": cmd_get,
        "set": cmd_set,
        "buzzer": cmd_buzzer,
        "lcd": cmd_lcd,
        "monitor": cmd_monitor,
    }
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
