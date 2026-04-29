#!/usr/bin/env python3
"""BetterKVM MCP Server — lab operations tooling for AI agents.

Exposes TESmart KVM switch control, machine mapping, serial console
info, and health checks via Model Context Protocol (stdio transport).
"""

import json
import os
import socket
import subprocess
import sys

MACHINE_MAP = {
    1: {"hostname": "honey", "arch": "x86_64", "serial_port": 3001},
    2: {"hostname": "bumble", "arch": "x86_64", "serial_port": 3002, "atx": True},
    3: {"hostname": "petting-zoo-mini", "arch": "aarch64", "serial_port": 3003},
    4: {"hostname": "xoxd-bates", "arch": "aarch64", "serial_port": 3004},
    5: {"hostname": "yoga", "arch": "x86_64", "serial_port": 3005},
    6: {"hostname": "mbp-13", "arch": "x86_64", "serial_port": 3006},
    7: {"hostname": "betsy", "arch": None, "serial_port": 3007},
    8: {"hostname": "musey", "arch": "riscv64", "serial_port": 3008},
    9: {"hostname": "sdr-1", "arch": None, "serial_port": 3009},
    10: {"hostname": "g2-1", "arch": "aarch64", "serial_port": 3010},
    11: {"hostname": "g2-2", "arch": "aarch64", "serial_port": 3011},
    12: {"hostname": "t-deck", "arch": "aarch64", "serial_port": 3012},
    13: {"hostname": "tdeck-pro", "arch": "aarch64", "serial_port": 3013},
    14: {"hostname": None, "arch": None, "serial_port": 3014},
    15: {"hostname": None, "arch": None, "serial_port": 3015},
    16: {"hostname": None, "arch": None, "serial_port": 3016},
}

TESMART_HOST = os.environ.get("TESMART_HOST", "10.0.0.50")
TESMART_PORT = int(os.environ.get("TESMART_PORT", "5000"))
SERIAL_CONSOLE_HOST = "serial-console"

HEADER = bytes([0xAA, 0xBB, 0x03])
FOOTER = bytes([0xEE])
CMD_SWITCH = 0x01
CMD_READ = 0x10
RESP_PORT = 0x11


def tesmart_send(cmd: int, value: int, expect_response: bool = False) -> bytes | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(3.0)
            sock.connect((TESMART_HOST, TESMART_PORT))
            sock.sendall(HEADER + bytes([cmd, value]) + FOOTER)
            if expect_response:
                import time
                time.sleep(0.2)
                return sock.recv(64)
    except (socket.timeout, ConnectionRefusedError, OSError):
        return None
    return None


def get_active_port() -> int | None:
    resp = tesmart_send(CMD_READ, 0x00, expect_response=True)
    if not resp or len(resp) < 6:
        return None
    idx = resp.find(bytes([0xAA, 0xBB, 0x03, RESP_PORT]))
    if idx == -1:
        return None
    val = resp[idx + 4]
    return val + 1 if val != 0xFF else None


def switch_port(port: int) -> dict:
    if not 1 <= port <= 16:
        return {"ok": False, "error": "Port must be 1-16"}
    tesmart_send(CMD_SWITCH, port)
    machine = MACHINE_MAP.get(port, {})
    return {
        "ok": True,
        "port": port,
        "hostname": machine.get("hostname"),
        "arch": machine.get("arch"),
    }


def check_tcp(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect((host, port))
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def ssh_service_status(host: str, service: str) -> dict:
    try:
        result = subprocess.run(
            ["ssh", "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=no",
             f"root@{host}", f"systemctl is-active {service}"],
            capture_output=True, text=True, timeout=10,
        )
        return {"active": result.stdout.strip() == "active", "status": result.stdout.strip()}
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return {"active": False, "status": "unreachable"}


def run_health_check() -> dict:
    results = {}
    results["tesmart"] = {
        "reachable": check_tcp(TESMART_HOST, TESMART_PORT),
        "active_port": get_active_port(),
    }

    results["serial_console"] = {
        "ssh_reachable": check_tcp(SERIAL_CONSOLE_HOST, 22),
    }

    if check_tcp(SERIAL_CONSOLE_HOST, 22):
        results["serial_console"]["ser2net"] = ssh_service_status(SERIAL_CONSOLE_HOST, "ser2net")
        results["serial_console"]["nut"] = ssh_service_status(SERIAL_CONSOLE_HOST, "nut-server")
        results["serial_console"]["tailscaled"] = ssh_service_status(SERIAL_CONSOLE_HOST, "tailscaled")

    pikvm_host = "pikvm-primary"
    results["pikvm"] = {"ssh_reachable": check_tcp(pikvm_host, 22)}
    if check_tcp(pikvm_host, 22):
        results["pikvm"]["kvmd"] = ssh_service_status(pikvm_host, "kvmd")
        results["pikvm"]["ustreamer"] = ssh_service_status(pikvm_host, "kvmd-streamer")
        results["pikvm"]["tailscaled"] = ssh_service_status(pikvm_host, "tailscaled")

    try:
        ts = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5,
        )
        if ts.returncode == 0:
            ts_data = json.loads(ts.stdout)
            results["tailscale"] = {
                "running": True,
                "self": ts_data.get("Self", {}).get("HostName"),
            }
        else:
            results["tailscale"] = {"running": False}
    except (FileNotFoundError, subprocess.TimeoutExpired):
        results["tailscale"] = {"running": False, "error": "tailscale not available"}

    return results


# --- MCP Protocol (JSON-RPC over stdio) ---

TOOLS = [
    {
        "name": "list_machines",
        "description": "List all 16 KVM port-to-machine mappings with hostname, architecture, and serial console port",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_active_port",
        "description": "Query the currently active TESmart KVM switch port",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "switch_port",
        "description": "Switch the TESmart KVM to a specific port (1-16). Use list_machines first to see port assignments.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "port": {
                    "type": "integer",
                    "description": "KVM port number (1-16)",
                    "minimum": 1,
                    "maximum": 16,
                },
            },
            "required": ["port"],
        },
    },
    {
        "name": "switch_to_machine",
        "description": "Switch the TESmart KVM to a machine by hostname (e.g., 'honey', 'bumble')",
        "inputSchema": {
            "type": "object",
            "properties": {
                "hostname": {
                    "type": "string",
                    "description": "Machine hostname",
                },
            },
            "required": ["hostname"],
        },
    },
    {
        "name": "health_check",
        "description": "Run health checks: TESmart reachability, active port, serial-console SSH, Tailscale status",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_serial_consoles",
        "description": "List available serial consoles with TCP port numbers for telnet access",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "get_machine_info",
        "description": "Get detailed info for a specific machine by hostname or port number",
        "inputSchema": {
            "type": "object",
            "properties": {
                "hostname": {"type": "string", "description": "Machine hostname"},
                "port": {"type": "integer", "description": "KVM port number (1-16)"},
            },
        },
    },
]


def handle_tool_call(name: str, arguments: dict) -> list:
    if name == "list_machines":
        machines = []
        for port_num, info in sorted(MACHINE_MAP.items()):
            machines.append({
                "kvm_port": port_num,
                "hostname": info["hostname"] or "(unassigned)",
                "arch": info["arch"],
                "serial_port": info["serial_port"],
                "atx_power": info.get("atx", False),
            })
        return [{"type": "text", "text": json.dumps(machines, indent=2)}]

    elif name == "get_active_port":
        port = get_active_port()
        if port is None:
            return [{"type": "text", "text": json.dumps({"error": "Could not read active port — TESmart may be unreachable"})}]
        machine = MACHINE_MAP.get(port, {})
        return [{"type": "text", "text": json.dumps({
            "active_port": port,
            "hostname": machine.get("hostname"),
            "arch": machine.get("arch"),
        })}]

    elif name == "switch_port":
        result = switch_port(arguments["port"])
        return [{"type": "text", "text": json.dumps(result)}]

    elif name == "switch_to_machine":
        hostname = arguments["hostname"].lower()
        for port_num, info in MACHINE_MAP.items():
            if info["hostname"] and info["hostname"].lower() == hostname:
                result = switch_port(port_num)
                return [{"type": "text", "text": json.dumps(result)}]
        return [{"type": "text", "text": json.dumps({"ok": False, "error": f"Unknown machine: {hostname}"})}]

    elif name == "health_check":
        return [{"type": "text", "text": json.dumps(run_health_check(), indent=2)}]

    elif name == "list_serial_consoles":
        consoles = []
        for port_num, info in sorted(MACHINE_MAP.items()):
            if info["hostname"]:
                consoles.append({
                    "hostname": info["hostname"],
                    "serial_port": info["serial_port"],
                    "connect": f"telnet {SERIAL_CONSOLE_HOST} {info['serial_port']}",
                })
        return [{"type": "text", "text": json.dumps(consoles, indent=2)}]

    elif name == "get_machine_info":
        target = None
        if "hostname" in arguments:
            hostname = arguments["hostname"].lower()
            for port_num, info in MACHINE_MAP.items():
                if info["hostname"] and info["hostname"].lower() == hostname:
                    target = (port_num, info)
                    break
        elif "port" in arguments:
            port_num = arguments["port"]
            if port_num in MACHINE_MAP:
                target = (port_num, MACHINE_MAP[port_num])

        if target is None:
            return [{"type": "text", "text": json.dumps({"error": "Machine not found"})}]

        port_num, info = target
        active = get_active_port()
        result = {
            "kvm_port": port_num,
            "hostname": info["hostname"],
            "arch": info["arch"],
            "serial_port": info["serial_port"],
            "serial_connect": f"telnet {SERIAL_CONSOLE_HOST} {info['serial_port']}",
            "atx_power": info.get("atx", False),
            "currently_active": active == port_num if active else None,
        }
        return [{"type": "text", "text": json.dumps(result)}]

    return [{"type": "text", "text": json.dumps({"error": f"Unknown tool: {name}"})}]


def send_response(response: dict):
    msg = json.dumps(response)
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = request.get("method")
        req_id = request.get("id")

        if method == "initialize":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {
                        "name": "betterkvm",
                        "version": "0.1.0",
                    },
                },
            })

        elif method == "notifications/initialized":
            pass

        elif method == "tools/list":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": TOOLS},
            })

        elif method == "tools/call":
            params = request.get("params", {})
            tool_name = params.get("name")
            arguments = params.get("arguments", {})
            try:
                content = handle_tool_call(tool_name, arguments)
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": content, "isError": False},
                })
            except Exception as e:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [{"type": "text", "text": json.dumps({"error": str(e)})}],
                        "isError": True,
                    },
                })

        elif method == "ping":
            send_response({"jsonrpc": "2.0", "id": req_id, "result": {}})

        else:
            if req_id is not None:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                })


if __name__ == "__main__":
    main()
