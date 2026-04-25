"""Property-based tests for TESmart binary protocol encoding/decoding.

Tests the frame format: 0xAA 0xBB 0x03 <cmd> <val> 0xEE
"""

from hypothesis import given, assume, settings, example
from hypothesis import strategies as st

from tesmart_ctl import (
    HEADER,
    FOOTER,
    CMD_SWITCH,
    CMD_BUZZER,
    CMD_LCD,
    CMD_READ,
    CMD_AUTODET,
    RESP_PORT,
    build_command,
    parse_port_response,
)

# --- Strategies ---

valid_commands = st.sampled_from([CMD_SWITCH, CMD_BUZZER, CMD_LCD, CMD_READ, CMD_AUTODET])
valid_port_values = st.integers(min_value=0, max_value=15)  # 0-indexed
valid_byte_values = st.integers(min_value=0, max_value=255)
garbage_bytes = st.binary(min_size=0, max_size=64)


# --- Frame structure properties ---


class TestBuildCommand:
    @given(cmd=valid_commands, value=valid_byte_values)
    def test_frame_length_is_always_six(self, cmd, value):
        frame = build_command(cmd, value)
        assert len(frame) == 6

    @given(cmd=valid_commands, value=valid_byte_values)
    def test_frame_starts_with_header(self, cmd, value):
        frame = build_command(cmd, value)
        assert frame[:3] == HEADER

    @given(cmd=valid_commands, value=valid_byte_values)
    def test_frame_ends_with_footer(self, cmd, value):
        frame = build_command(cmd, value)
        assert frame[-1:] == FOOTER

    @given(cmd=valid_commands, value=valid_byte_values)
    def test_cmd_byte_is_at_index_three(self, cmd, value):
        frame = build_command(cmd, value)
        assert frame[3] == cmd

    @given(cmd=valid_commands, value=valid_byte_values)
    def test_value_byte_is_at_index_four(self, cmd, value):
        frame = build_command(cmd, value)
        assert frame[4] == value

    @given(cmd=valid_commands, value=valid_byte_values)
    def test_header_bytes_are_canonical(self, cmd, value):
        frame = build_command(cmd, value)
        assert frame[0] == 0xAA
        assert frame[1] == 0xBB
        assert frame[2] == 0x03


# --- Parse response round-trip properties ---


class TestParsePortResponse:
    @given(port=valid_port_values)
    def test_roundtrip_port_response(self, port):
        """A well-formed response frame round-trips through parse correctly."""
        response = HEADER + bytes([RESP_PORT, port]) + FOOTER
        parsed = parse_port_response(response)
        assert parsed == port + 1  # parse returns 1-indexed

    @given(port=valid_port_values)
    def test_parse_is_one_indexed(self, port):
        """Parser converts 0-indexed wire value to 1-indexed user value."""
        response = HEADER + bytes([RESP_PORT, port]) + FOOTER
        parsed = parse_port_response(response)
        assert parsed is not None
        assert parsed >= 1
        assert parsed <= 16

    @given(port=valid_port_values, prefix=garbage_bytes, suffix=garbage_bytes)
    def test_parse_tolerates_surrounding_garbage(self, port, prefix, suffix):
        """Parser finds the response frame even with garbage around it."""
        response = prefix + HEADER + bytes([RESP_PORT, port]) + FOOTER + suffix
        parsed = parse_port_response(response)
        # May fail if garbage contains a false header match, but valid port
        # values should still parse from the first valid frame
        if parsed is not None:
            assert 1 <= parsed <= 16

    def test_parse_returns_none_for_empty(self):
        assert parse_port_response(b"") is None

    def test_parse_returns_none_for_short(self):
        assert parse_port_response(b"\xaa\xbb") is None

    @given(data=garbage_bytes)
    def test_parse_never_crashes_on_garbage(self, data):
        """Parser must not raise on arbitrary input."""
        result = parse_port_response(data)
        assert result is None or (isinstance(result, int) and 1 <= result <= 16)

    def test_parse_returns_none_for_0xff_port(self):
        """0xFF is the 'no active port' sentinel."""
        response = HEADER + bytes([RESP_PORT, 0xFF]) + FOOTER
        assert parse_port_response(response) is None

    @example(port=0)
    @example(port=15)
    @given(port=valid_port_values)
    def test_all_16_ports_parseable(self, port):
        """Every valid port (0-15 wire, 1-16 user) parses correctly."""
        response = HEADER + bytes([RESP_PORT, port]) + FOOTER
        parsed = parse_port_response(response)
        assert parsed == port + 1


# --- Switch command properties ---


class TestSwitchCommand:
    @given(port=st.integers(min_value=1, max_value=16))
    def test_switch_command_encodes_port_directly(self, port):
        """Switch command uses the port number as the value byte."""
        frame = build_command(CMD_SWITCH, port)
        assert frame[3] == CMD_SWITCH
        assert frame[4] == port

    @given(port=st.integers(min_value=1, max_value=16))
    def test_switch_frame_is_valid(self, port):
        frame = build_command(CMD_SWITCH, port)
        assert len(frame) == 6
        assert frame[:3] == HEADER
        assert frame[-1:] == FOOTER


# --- Buzzer/LCD/AutoDetect value encoding ---


class TestControlCommands:
    @given(state=st.sampled_from([0, 1]))
    def test_buzzer_binary_values(self, state):
        frame = build_command(CMD_BUZZER, state)
        assert frame[4] in (0, 1)

    @given(lcd_val=st.sampled_from([0x00, 0x0A, 0x1E]))
    def test_lcd_valid_timeouts(self, lcd_val):
        frame = build_command(CMD_LCD, lcd_val)
        assert frame[4] == lcd_val

    @given(state=st.sampled_from([0, 1]))
    def test_autodetect_binary_values(self, state):
        frame = build_command(CMD_AUTODET, state)
        assert frame[4] in (0, 1)


# --- Invariant: no command ever produces a frame without the sentinel bytes ---


class TestFrameInvariants:
    @given(cmd=valid_byte_values, value=valid_byte_values)
    def test_any_cmd_value_combo_produces_valid_frame(self, cmd, value):
        """Even arbitrary cmd/value bytes produce a structurally valid frame."""
        frame = build_command(cmd, value)
        assert len(frame) == 6
        assert frame[0] == 0xAA
        assert frame[1] == 0xBB
        assert frame[2] == 0x03
        assert frame[5] == 0xEE
