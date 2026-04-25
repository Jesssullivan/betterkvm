"""Property-based tests for machine mapping and ser2net port consistency.

Validates invariants across the 16-port machine map, serial console
port assignments, and KVM-to-serial alignment.
"""

import sys
from pathlib import Path

from hypothesis import given, assume, settings
from hypothesis import strategies as st

# Add mcp server to path for MACHINE_MAP
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "mcp"))
from server import MACHINE_MAP, TOOLS, handle_tool_call


class TestMachineMapStructure:
    def test_exactly_16_ports(self):
        assert len(MACHINE_MAP) == 16

    def test_ports_are_1_through_16(self):
        assert set(MACHINE_MAP.keys()) == set(range(1, 17))

    def test_all_entries_have_required_keys(self):
        for port, info in MACHINE_MAP.items():
            assert "hostname" in info, f"Port {port} missing hostname"
            assert "arch" in info, f"Port {port} missing arch"
            assert "serial_port" in info, f"Port {port} missing serial_port"

    def test_serial_ports_are_contiguous_from_3001(self):
        for port in range(1, 17):
            assert MACHINE_MAP[port]["serial_port"] == 3000 + port

    def test_no_duplicate_hostnames(self):
        hostnames = [
            info["hostname"]
            for info in MACHINE_MAP.values()
            if info["hostname"] is not None
        ]
        assert len(hostnames) == len(set(hostnames))

    def test_no_duplicate_serial_ports(self):
        serial_ports = [info["serial_port"] for info in MACHINE_MAP.values()]
        assert len(serial_ports) == len(set(serial_ports))

    def test_assigned_machines_have_hostnames(self):
        """Ports 1-13 are assigned and should have hostnames."""
        for port in range(1, 14):
            assert MACHINE_MAP[port]["hostname"] is not None, f"Port {port} should be assigned"

    def test_unassigned_ports_have_no_hostname(self):
        """Ports 14-16 are spare and should have no hostname."""
        for port in range(14, 17):
            assert MACHINE_MAP[port]["hostname"] is None, f"Port {port} should be unassigned"

    def test_arch_values_are_valid(self):
        valid_archs = {"x86_64", "aarch64", "riscv64", None}
        for port, info in MACHINE_MAP.items():
            assert info["arch"] in valid_archs, f"Port {port} has invalid arch: {info['arch']}"

    def test_serial_ports_in_valid_range(self):
        for port, info in MACHINE_MAP.items():
            assert 3001 <= info["serial_port"] <= 3016


class TestMCPToolDefinitions:
    def test_all_tools_have_name_and_description(self):
        for tool in TOOLS:
            assert "name" in tool
            assert "description" in tool
            assert len(tool["description"]) > 10

    def test_all_tools_have_input_schema(self):
        for tool in TOOLS:
            assert "inputSchema" in tool
            assert tool["inputSchema"]["type"] == "object"

    def test_tool_names_are_unique(self):
        names = [t["name"] for t in TOOLS]
        assert len(names) == len(set(names))

    def test_expected_tools_exist(self):
        names = {t["name"] for t in TOOLS}
        expected = {
            "list_machines",
            "get_active_port",
            "switch_port",
            "switch_to_machine",
            "health_check",
            "list_serial_consoles",
            "get_machine_info",
        }
        assert expected <= names


class TestToolHandlers:
    def test_list_machines_returns_all_16(self):
        result = handle_tool_call("list_machines", {})
        import json
        data = json.loads(result[0]["text"])
        assert len(data) == 16

    @given(port=st.integers(min_value=1, max_value=16))
    @settings(deadline=None)
    def test_get_machine_info_by_port(self, port):
        import json
        result = handle_tool_call("get_machine_info", {"port": port})
        data = json.loads(result[0]["text"])
        assert data["kvm_port"] == port
        assert data["serial_port"] == 3000 + port

    def test_switch_to_unknown_machine_returns_error(self):
        import json
        result = handle_tool_call("switch_to_machine", {"hostname": "nonexistent"})
        data = json.loads(result[0]["text"])
        assert data["ok"] is False

    @given(port=st.integers(min_value=17, max_value=100))
    def test_switch_invalid_port_returns_error(self, port):
        import json
        result = handle_tool_call("switch_port", {"port": port})
        data = json.loads(result[0]["text"])
        assert data["ok"] is False

    def test_unknown_tool_returns_error(self):
        import json
        result = handle_tool_call("nonexistent_tool", {})
        data = json.loads(result[0]["text"])
        assert "error" in data

    def test_list_serial_consoles_has_connect_strings(self):
        import json
        result = handle_tool_call("list_serial_consoles", {})
        data = json.loads(result[0]["text"])
        for console in data:
            assert "connect" in console
            assert "telnet" in console["connect"]
            assert "hostname" in console

    @given(hostname=st.sampled_from([
        "honey", "bumble", "petting-zoo-mini", "xoxd-bates",
        "yoga", "mbp-13", "betsy", "musey", "sdr-1",
        "g2-1", "g2-2", "t-deck", "tdeck-pro",
    ]))
    @settings(deadline=None)
    def test_get_machine_info_by_hostname(self, hostname):
        import json
        result = handle_tool_call("get_machine_info", {"hostname": hostname})
        data = json.loads(result[0]["text"])
        assert data["hostname"] == hostname
        assert 1 <= data["kvm_port"] <= 16
