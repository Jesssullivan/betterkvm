# tests/vm/nut.nix — TIN-539
#
# NixOS VM test for NUT (Network UPS Tools) in netserver mode, using the
# `dummy-ups` driver so no physical UPS is required. This deliberately does
# NOT import modules/nut-server directly: that module wires
# `config.sops.secrets.nut-password.path`, which needs live sops-nix
# secrets infrastructure this hermetic VM does not have. Instead it
# reconstructs the same `power.ups` shape (netserver mode, upsd listening,
# upsmon primary monitor) using a `pkgs.writeText` password file in place
# of a sops secret, which is the documented safe substitution for a VM
# test of module *logic*.
#
# Verified against the live module source
# (nixos/modules/services/monitoring/ups.nix, nixos-24.11) rather than
# assumed:
#   * NUT_CONFPATH is hardcoded to /etc/nut -- not host/version-dependent.
#   * the systemd units are upsd.service, upsdrv.service (a oneshot that
#     runs `upsdrvctl start` for every configured UPS, NOT one unit per
#     UPS) and upsmon.service.
#   * `users.<name>` and `upsmon.monitor.<name>` only accept
#     `passwordFile`, never a plaintext `password`.
{ pkgs, ... }:

let
  testPasswordFile = pkgs.writeText "nut-vm-test-password" "vm-test-only-not-a-real-secret";
in
pkgs.testers.runNixOSTest {
  name = "nut";

  nodes.machine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nut ];

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
            port = 3493;
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
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("write the dummy-ups simulated reading file"):
        # NUT_CONFPATH is fixed at /etc/nut by the module; dummy-ups reads
        # its simulated readings from <confpath>/<port>.
        machine.succeed(
            "cat > /etc/nut/dummy-ups.dev <<'DUMMYEOF'\n"
            "battery.charge: 100\n"
            "battery.runtime: 3600\n"
            "ups.status: OL\n"
            "ups.mfr: Dummy\n"
            "ups.model: VM Test UPS\n"
            "DUMMYEOF\n"
        )

    with subtest("upsd starts and serves on the configured port"):
        machine.succeed("systemctl restart upsd.service")
        machine.wait_for_unit("upsd.service")
        machine.wait_for_open_port(3493)

    with subtest("upsdrv registers the dummy driver against the reading file"):
        # upsdrv is a oneshot (RemainAfterExit); restarting re-runs
        # `upsdrvctl start` now that both upsd and the reading file exist.
        machine.succeed("systemctl restart upsdrv.service")
        machine.wait_for_unit("upsdrv.service")

    with subtest("upsc query returns the dummy reading"):
        status = machine.succeed("upsc dummy-ups@localhost ups.status").strip()
        assert "OL" in status, f"expected OL status, got: {status!r}"
        charge = machine.succeed("upsc dummy-ups@localhost battery.charge").strip()
        assert charge == "100", f"expected battery.charge 100, got: {charge!r}"

    with subtest("upsmon comes up and can reach upsd"):
        machine.wait_for_unit("upsmon.service")

    with subtest("firewall opens the configured upsd port"):
        fw = machine.succeed("iptables -L INPUT -n")
        assert "3493" in fw, "configured NUT port is not in the firewall accept rules"
  '';
}
