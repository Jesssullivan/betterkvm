# tests/vm/tailscale.nix — TIN-539
#
# NixOS VM test for the tailscale subnet-router posture used by
# hosts/common/tailscale.nix. Does not import that file directly: it wires
# `authKeyFile = config.sops.secrets.tailscale-auth-key.path`, which needs
# live sops-nix secrets this hermetic VM does not have. This test
# reconstructs the same `services.tailscale` + firewall shape without an
# auth key -- tailscaled starts and is reachable, it just reports
# "not logged in" (no network join is attempted or expected).
#
# Verified against the live module source
# (nixos/modules/services/networking/tailscale.nix, nixos-24.11):
#   * the daemon's own shipped unit is `tailscaled.service` (this module
#     only sets its Environment, via `systemd.packages = [ cfg.package ]`).
#   * `useRoutingFeatures = "server"` sets
#     `boot.kernel.sysctl."net.ipv4.conf.all.forwarding"` (and the ipv6
#     equivalent) to true -- that is the actual forwarding assertion this
#     test makes, matching what the module claims rather than a general
#     "IP forwarding enabled" guess.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "tailscale";

  nodes.machine =
    { config, ... }:
    {
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

    with subtest("tailscaled starts without an auth key"):
        machine.wait_for_unit("tailscaled.service")

    with subtest("tailscale reports not logged in (no join was attempted)"):
        status = machine.succeed("tailscale status 2>&1 || true")
        assert "Logged out" in status or "NeedsLogin" in status or "not logged in" in status.lower(), (
            f"expected an unauthenticated status, got: {status!r}"
        )

    with subtest("firewall trusts the tailscale0 interface"):
        trusted = machine.succeed("iptables -L INPUT -n -v")
        # nixpkgs' firewall implementation adds an ACCEPT rule keyed on the
        # trusted interface name; assert the interface name appears in the
        # accept chain rather than parsing exact iptables formatting.
        assert "tailscale0" in trusted, "tailscale0 is not a trusted firewall interface"

    with subtest("IPv4 and IPv6 forwarding are enabled by useRoutingFeatures=server"):
        ipv4_forward = machine.succeed("cat /proc/sys/net/ipv4/conf/all/forwarding").strip()
        ipv6_forward = machine.succeed("cat /proc/sys/net/ipv6/conf/all/forwarding").strip()
        assert ipv4_forward == "1", f"expected IPv4 forwarding enabled, got: {ipv4_forward!r}"
        assert ipv6_forward == "1", f"expected IPv6 forwarding enabled, got: {ipv6_forward!r}"
  '';
}
