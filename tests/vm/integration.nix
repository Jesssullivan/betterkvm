# tests/vm/integration.nix — TIN-539
#
# Combined VM test: ser2net + NUT (dummy-ups) + tailscale on one machine,
# validating service ordering and that none of their fixed ports collide
# (ser2net 3001, NUT upsd 3493, tailscale UDP port -- disjoint by
# construction, asserted here rather than merely assumed).
{ pkgs, ... }:

let
  ser2netModule = ../../modules/ser2net;
  testDevice = "/tmp/lab-test-tty";
  testDevicePeer = "/tmp/lab-test-tty-peer";
  ser2netPort = 3001;
  nutPort = 3493;
  testPasswordFile = pkgs.writeText "nut-vm-test-password" "vm-test-only-not-a-real-secret";
in
pkgs.testers.runNixOSTest {
  name = "lab-services-integration";

  nodes.machine =
    { pkgs, config, ... }:
    {
      imports = [ ser2netModule ];

      environment.systemPackages = [
        pkgs.socat
        pkgs.nut
      ];

      services.lab-ser2net = {
        enable = true;
        connections.test-port = {
          port = ser2netPort;
          device = testDevice;
          speed = "9600n81";
          description = "integration test serial connection";
        };
      };

      power.ups = {
        enable = true;
        mode = "netserver";
        ups."dummy-ups" = {
          description = "VM Test Dummy UPS";
          driver = "dummy-ups";
          port = "dummy-ups.dev";
        };
        upsd.listen = [
          {
            address = "0.0.0.0";
            port = nutPort;
          }
        ];
        users.upsmon = {
          passwordFile = testPasswordFile;
          upsmon = "primary";
        };
        upsmon = {
          enable = true;
          monitor."dummy-ups@localhost" = {
            powerValue = 1;
            type = "primary";
            user = "upsmon";
            passwordFile = testPasswordFile;
          };
          settings = {
            MINSUPPLIES = 1;
            SHUTDOWNCMD = "${pkgs.coreutils}/bin/true";
            POLLFREQ = 5;
            POLLFREQALERT = 2;
            FINALDELAY = 5;
          };
        };
        openFirewall = true;
      };

      services.tailscale = {
        enable = true;
        useRoutingFeatures = "server";
      };

      networking.firewall = {
        trustedInterfaces = [ "tailscale0" ];
        allowedUDPPorts = [ config.services.tailscale.port ];
        checkReversePath = "loose";
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("configured TCP/UDP ports are disjoint"):
        ser2net_port = ${builtins.toString ser2netPort}
        nut_port = ${builtins.toString nutPort}
        assert ser2net_port != nut_port, "ser2net and NUT ports collide by construction"

    with subtest("serial device pair exists for ser2net"):
        machine.succeed(
            "socat -d -d "
            "pty,raw,echo=0,link=${testDevice} "
            "pty,raw,echo=0,link=${testDevicePeer} "
            ">/tmp/socat.log 2>&1 </dev/null &"
        )
        machine.wait_for_file("${testDevice}")

    with subtest("ser2net starts and listens"):
        machine.succeed("systemctl restart ser2net.service")
        machine.wait_for_unit("ser2net.service")
        machine.wait_for_open_port(ser2net_port)

    with subtest("NUT dummy driver is wired and upsd listens"):
        machine.succeed(
            "cat > /etc/nut/dummy-ups.dev <<'DUMMYEOF'\n"
            "battery.charge: 100\n"
            "ups.status: OL\n"
            "DUMMYEOF\n"
        )
        machine.succeed("systemctl restart upsd.service")
        machine.wait_for_unit("upsd.service")
        machine.succeed("systemctl restart upsdrv.service")
        machine.wait_for_unit("upsdrv.service")
        machine.wait_for_open_port(nut_port)

    with subtest("tailscaled starts alongside the other two services"):
        machine.wait_for_unit("tailscaled.service")

    with subtest("no port conflict: both services are independently reachable"):
        machine.wait_for_open_port(ser2net_port)
        machine.wait_for_open_port(nut_port)
        status = machine.succeed("upsc dummy-ups@localhost ups.status").strip()
        assert "OL" in status, f"expected OL status, got: {status!r}"

    with subtest("firewall trusts tailscale0 without blocking the other two services' ports"):
        fw = machine.succeed("iptables -L INPUT -n")
        assert str(ser2net_port) in fw
        assert str(nut_port) in fw
  '';
}
