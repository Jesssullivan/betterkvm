# tests/vm/ser2net.nix — TIN-539
#
# NixOS VM test for modules/ser2net: validates the module's generated
# systemd unit, config, and firewall rule without any physical serial
# hardware. A `socat` PTY pair stands in for the serial device the module
# expects at `conn.device`; ser2net's own `Restart = "on-failure"` policy
# means start order between socat and ser2net does not matter.
#
# Run via `nix flake check` (CI only — this repo's local dev machine does
# not build/eval; see justfile/CI for the sanctioned entry point).
{ pkgs, ... }:

let
  ser2netModule = ../../modules/ser2net;
  testDevice = "/tmp/lab-test-tty";
  testDevicePeer = "/tmp/lab-test-tty-peer";
  testPort = 3001;
  testDescription = "VM test serial connection";
in
pkgs.testers.runNixOSTest {
  name = "ser2net";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ser2netModule ];

      environment.systemPackages = [ pkgs.socat ];

      services.lab-ser2net = {
        enable = true;
        connections.test-port = {
          port = testPort;
          device = testDevice;
          speed = "9600n81";
          description = testDescription;
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("generated config carries the module's own values"):
        config_text = machine.succeed("cat /etc/ser2net/ser2net.yaml")
        assert "${builtins.toString testPort}" in config_text, "port missing from generated config"
        assert "${testDevice}" in config_text, "device path missing from generated config"
        assert "${testDescription}" in config_text, "banner description missing from generated config"

    with subtest("firewall opens the configured port"):
        fw = machine.succeed("iptables -L INPUT -n")
        assert "${builtins.toString testPort}" in fw, "configured port is not in the firewall accept rules"

    with subtest("serial device pair exists before ser2net needs it"):
        # Trailing `&` backgrounds socat so `succeed()` (which waits for the
        # shell it runs to exit) returns immediately instead of blocking on
        # a long-running process; redirecting all three fds detaches it from
        # the test driver's connection.
        machine.succeed(
            "socat -d -d "
            "pty,raw,echo=0,link=${testDevice} "
            "pty,raw,echo=0,link=${testDevicePeer} "
            ">/tmp/socat.log 2>&1 </dev/null &"
        )
        machine.wait_for_file("${testDevice}")
        machine.wait_for_file("${testDevicePeer}")

    with subtest("ser2net starts once its serial device is available"):
        # The module sets Restart=on-failure/RestartSec=5, so a restart here
        # (rather than relying on the original boot-time attempt) proves the
        # service can recover once the device shows up, which is the real
        # startup order on physical hardware too (USB serial adapters attach
        # after boot).
        machine.succeed("systemctl restart ser2net.service")
        machine.wait_for_unit("ser2net.service")
        machine.wait_for_open_port(${builtins.toString testPort})

    with subtest("connecting over TCP reaches the configured serial device"):
        # ser2net sends its configured banner over the TCP side immediately
        # on accept, before any serial-side bytes flow, so receiving it here
        # proves the full accepter -> connector -> serial-device chain is
        # live, not just that something is listening on the port.
        banner = machine.succeed(
            "timeout 5 bash -c "
            "'exec 3<>/dev/tcp/127.0.0.1/${builtins.toString testPort}; head -c 200 <&3'"
        )
        assert "${testDescription}" in banner, f"banner missing expected description, got: {banner!r}"
  '';
}
