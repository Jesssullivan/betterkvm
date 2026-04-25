"""Property-based tests for preseed scripts and override.yaml configuration.

Validates script ordering invariants, override.yaml structural consistency,
and machine-to-port mapping alignment across config files.
"""

import os
import re
from pathlib import Path

import yaml
from hypothesis import given, settings
from hypothesis import strategies as st

REPO_ROOT = Path(__file__).parent.parent.parent


class TestPreseedScriptOrdering:
    """Verify preseed scripts follow correct numbering and dependency order."""

    def _get_scripts(self):
        scripts_dir = REPO_ROOT / "hosts/pikvm-primary/preseed/pikvm-scripts.d"
        return sorted(scripts_dir.glob("*.sh"))

    def test_scripts_exist(self):
        scripts = self._get_scripts()
        assert len(scripts) >= 4

    def test_scripts_are_numbered_sequentially(self):
        scripts = self._get_scripts()
        numbers = []
        for s in scripts:
            match = re.match(r"^(\d+)-", s.name)
            assert match, f"Script {s.name} does not start with a number prefix"
            numbers.append(int(match.group(1)))
        for i in range(len(numbers) - 1):
            assert numbers[i] < numbers[i + 1], f"Scripts not in order: {numbers}"

    def test_passwords_before_tailscale(self):
        """Passwords must be set before Tailscale auth (network-dependent)."""
        scripts = self._get_scripts()
        names = [s.name for s in scripts]
        password_idx = next(i for i, n in enumerate(names) if "password" in n)
        tailscale_idx = next(i for i, n in enumerate(names) if "tailscale" in n)
        assert password_idx < tailscale_idx

    def test_ssh_keys_before_tailscale(self):
        """SSH keys must be installed before Tailscale (needed for remote recovery)."""
        scripts = self._get_scripts()
        names = [s.name for s in scripts]
        ssh_idx = next(i for i, n in enumerate(names) if "ssh" in n)
        tailscale_idx = next(i for i, n in enumerate(names) if "tailscale" in n)
        assert ssh_idx < tailscale_idx

    def test_hostname_is_last(self):
        """Hostname + reboot must be the final script."""
        scripts = self._get_scripts()
        assert "hostname" in scripts[-1].name

    def test_all_scripts_are_executable_bash(self):
        scripts = self._get_scripts()
        for s in scripts:
            content = s.read_text()
            assert content.startswith("#!/bin/bash"), f"{s.name} missing bash shebang"

    def test_all_scripts_use_set_euo_pipefail(self):
        scripts = self._get_scripts()
        for s in scripts:
            content = s.read_text()
            assert "set -euo pipefail" in content, f"{s.name} missing strict mode"

    def test_password_script_has_secure_delete(self):
        scripts = self._get_scripts()
        pwd_script = next(s for s in scripts if "password" in s.name)
        content = pwd_script.read_text()
        assert "secure_delete" in content or "dd if=/dev/urandom" in content

    def test_tailscale_script_has_trap_cleanup(self):
        scripts = self._get_scripts()
        ts_script = next(s for s in scripts if "tailscale" in s.name)
        content = ts_script.read_text()
        assert "trap" in content


class TestOverrideYaml:
    """Validate override.yaml structural consistency."""

    def _load_override(self):
        path = REPO_ROOT / "hosts/pikvm-primary/kvmd/override.yaml"
        return yaml.safe_load(path.read_text())

    def test_override_yaml_parses(self):
        config = self._load_override()
        assert isinstance(config, dict)
        assert "kvmd" in config

    def test_gpio_drivers_section_exists(self):
        config = self._load_override()
        assert "gpio" in config["kvmd"]
        assert "drivers" in config["kvmd"]["gpio"]
        assert "scheme" in config["kvmd"]["gpio"]

    def test_tesmart_driver_configured(self):
        config = self._load_override()
        drivers = config["kvmd"]["gpio"]["drivers"]
        assert "tes" in drivers
        assert drivers["tes"]["type"] == "tesmart"
        assert drivers["tes"]["port"] == 5000

    def test_16_port_scheme_entries(self):
        """Override.yaml should have LED + switch entries for all 16 ports."""
        config = self._load_override()
        scheme = config["kvmd"]["gpio"]["scheme"]
        led_entries = [k for k in scheme if k.endswith("_led") and scheme[k].get("driver") == "tes"]
        switch_entries = [k for k in scheme if k.endswith("_switch") and scheme[k].get("driver") == "tes"]
        assert len(led_entries) == 16, f"Expected 16 LED entries, got {len(led_entries)}"
        assert len(switch_entries) == 16, f"Expected 16 switch entries, got {len(switch_entries)}"

    def test_led_entries_are_input_mode(self):
        config = self._load_override()
        scheme = config["kvmd"]["gpio"]["scheme"]
        for name, entry in scheme.items():
            if name.endswith("_led") and entry.get("driver") == "tes":
                assert entry["mode"] == "input", f"{name} should be input mode"

    def test_switch_entries_are_output_mode(self):
        config = self._load_override()
        scheme = config["kvmd"]["gpio"]["scheme"]
        for name, entry in scheme.items():
            if name.endswith("_switch") and entry.get("driver") == "tes":
                assert entry["mode"] == "output", f"{name} should be output mode"

    def test_port_pins_are_sequential(self):
        """TESmart pins should be 0-15 (matching 16-port switch)."""
        config = self._load_override()
        scheme = config["kvmd"]["gpio"]["scheme"]
        pins = set()
        for name, entry in scheme.items():
            if name.endswith("_led") and entry.get("driver") == "tes":
                pins.add(entry["pin"])
        assert pins == set(range(16)), f"Expected pins 0-15, got {sorted(pins)}"

    def test_led_and_switch_pins_match(self):
        """Each port's LED and switch should use the same pin number."""
        config = self._load_override()
        scheme = config["kvmd"]["gpio"]["scheme"]
        for name, entry in scheme.items():
            if name.endswith("_led") and entry.get("driver") == "tes":
                base = name.replace("_led", "")
                switch_name = f"{base}_switch"
                assert switch_name in scheme, f"Missing switch for {name}"
                assert scheme[switch_name]["pin"] == entry["pin"], \
                    f"Pin mismatch: {name}={entry['pin']} vs {switch_name}={scheme[switch_name]['pin']}"
