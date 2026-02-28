#!/usr/bin/env python3
"""tesmart-ctl: CLI for TESmart KVM switch control over TCP or RS232 serial.

Usage:
    tesmart-ctl get                     Query active port
    tesmart-ctl set <port>              Switch to port (1-based)
    tesmart-ctl buzzer <on|off>         Control buzzer
    tesmart-ctl lcd <0|10|30>           LCD timeout in seconds
    tesmart-ctl autodetect <on|off>     Toggle input auto-detection
    tesmart-ctl info                    Query active port + network config
    tesmart-ctl monitor                 Continuously poll and display port

Protocol: 0xAA 0xBB 0x03 <cmd> <val> 0xEE over TCP (default 192.168.1.10:5000)
          Same binary protocol over RS232 at 9600 8N1

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

SERIAL_BAUD = 9600


def build_command(cmd: int, value: int) -> bytes:
    return HEADER + bytes([cmd, value]) + FOOTER


class TCPTransport:
    """TCP socket transport for TESmart control."""

    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port

    def send(self, data: bytes, expect_response: bool = False) -> bytes | None:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect((self.host, self.port))
            sock.sendall(data)
            if expect_response:
                time.sleep(0.2)
                return sock.recv(64)
        return None

    def send_ascii(self, query: str) -> str:
        """Send ASCII query (e.g. 'IP?') and read response line."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(TIMEOUT)
            sock.connect((self.host, self.port))
            sock.sendall((query + "\r\n").encode())
            time.sleep(0.3)
            return sock.recv(256).decode(errors="replace").strip()


class SerialTransport:
    """RS232 serial transport for TESmart control (9600 8N1)."""

    def __init__(self, device: str):
        self.device = device

    def send(self, data: bytes, expect_response: bool = False) -> bytes | None:
        fd = os.open(self.device, os.O_RDWR | os.O_NOCTTY)
        try:
            # Configure serial port via termios
            import termios
            attrs = termios.tcgetattr(fd)
            # Input flags: no parity, no flow control
            attrs[0] = 0
            # Output flags: raw
            attrs[1] = 0
            # Control flags: 8N1, local, read enable
            attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
            # Local flags: raw
            attrs[3] = 0
            # Set baud rate
            attrs[4] = termios.B9600  # ispeed
            attrs[5] = termios.B9600  # ospeed
            # cc: VMIN=1, VTIME=30 (3s timeout)
            attrs[6][termios.VMIN] = 0
            attrs[6][termios.VTIME] = 30
            termios.tcsetattr(fd, termios.TCSANOW, attrs)
            termios.tcflush(fd, termios.TCIOFLUSH)

            os.write(fd, data)
            if expect_response:
                time.sleep(0.3)
                return os.read(fd, 64)
        finally:
            os.close(fd)
        return None

    def send_ascii(self, query: str) -> str:
        """Send ASCII query over serial and read response."""
        fd = os.open(self.device, os.O_RDWR | os.O_NOCTTY)
        try:
            import termios
            attrs = termios.tcgetattr(fd)
            attrs[0] = 0
            attrs[1] = 0
            attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
            attrs[3] = 0
            attrs[4] = termios.B9600
            attrs[5] = termios.B9600
            attrs[6][termios.VMIN] = 0
            attrs[6][termios.VTIME] = 30
            termios.tcsetattr(fd, termios.TCSANOW, attrs)
            termios.tcflush(fd, termios.TCIOFLUSH)

            os.write(fd, (query + "\r\n").encode())
            time.sleep(0.3)
            return os.read(fd, 256).decode(errors="replace").strip()
        finally:
            os.close(fd)


def get_transport(args):
    """Return the appropriate transport based on args."""
    if hasattr(args, "serial") and args.serial:
        return SerialTransport(args.serial)
    return TCPTransport(args.host, args.port)


def send_command(transport, cmd: int, value: int,
                 expect_response: bool = False) -> bytes | None:
    frame = build_command(cmd, value)
    return transport.send(frame, expect_response)


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
    transport = get_transport(args)
    for attempt in range(RETRY_COUNT):
        try:
            resp = send_command(transport, CMD_READ, 0x00,
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
    transport = get_transport(args)
    try:
        send_command(transport, CMD_SWITCH, target)
        print(f"Switched to port {target}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_buzzer(args):
    val = 1 if args.state in ("on", "1") else 0
    transport = get_transport(args)
    try:
        send_command(transport, CMD_BUZZER, val)
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
    transport = get_transport(args)
    try:
        send_command(transport, CMD_LCD, val)
        label = "never" if args.seconds == "0" else f"{args.seconds}s"
        print(f"LCD timeout: {label}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_autodetect(args):
    val = 1 if args.state in ("on", "1") else 0
    transport = get_transport(args)
    try:
        send_command(transport, CMD_AUTODET, val)
        print(f"Auto-detect {'on' if val else 'off'}")
        return 0
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


def cmd_info(args):
    transport = get_transport(args)
    # Query active port
    for attempt in range(RETRY_COUNT):
        try:
            resp = send_command(transport, CMD_READ, 0x00,
                                expect_response=True)
            port = parse_port_response(resp)
            if port is not None:
                print(f"Active port: {port}")
                break
        except (socket.timeout, ConnectionRefusedError, OSError) as e:
            if attempt == RETRY_COUNT - 1:
                print(f"Active port: ERROR ({e})", file=sys.stderr)
        if attempt < RETRY_COUNT - 1:
            time.sleep(RETRY_DELAY)

    # Query ASCII network config (TCP only)
    if isinstance(transport, TCPTransport):
        for query, label in [("IP?", "IP Address"), ("PT?", "TCP Port"),
                             ("GW?", "Gateway"), ("MA?", "MAC Address")]:
            try:
                resp = transport.send_ascii(query)
                if resp:
                    print(f"{label}: {resp}")
            except (socket.timeout, ConnectionRefusedError, OSError):
                print(f"{label}: N/A")
    else:
        print("(Network config queries not available over serial)")
    return 0


def cmd_monitor(args):
    print("Monitoring TESmart switch (Ctrl+C to stop)...")
    transport = get_transport(args)
    last_port = None
    while True:
        try:
            resp = send_command(transport, CMD_READ, 0x00,
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
    parser.add_argument("--serial",
                        help="Serial device for RS232 control (e.g. /dev/ttyUSB0)")

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("get", help="Query active port")

    p_set = sub.add_parser("set", help="Switch to port N")
    p_set.add_argument("target", help="Port number (1-16)")

    p_buzz = sub.add_parser("buzzer", help="Control buzzer")
    p_buzz.add_argument("state", choices=["on", "off", "0", "1"])

    p_lcd = sub.add_parser("lcd", help="Set LCD timeout")
    p_lcd.add_argument("seconds", choices=["0", "10", "30"])

    p_autodetect = sub.add_parser("autodetect", help="Toggle input auto-detection")
    p_autodetect.add_argument("state", choices=["on", "off", "0", "1"])

    sub.add_parser("info", help="Query port and network configuration")

    sub.add_parser("monitor", help="Continuously poll port changes")

    args = parser.parse_args()
    handlers = {
        "get": cmd_get,
        "set": cmd_set,
        "buzzer": cmd_buzzer,
        "lcd": cmd_lcd,
        "autodetect": cmd_autodetect,
        "info": cmd_info,
        "monitor": cmd_monitor,
    }
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
