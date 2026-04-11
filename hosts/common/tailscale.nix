{ config, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server"; # Enable subnet routing capability
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
  };

  # Firewall rules for Tailscale
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose"; # Required for subnet routing
  };

  # After first boot, manually join:
  #   sudo tailscale up --advertise-routes=10.0.0.0/24 --accept-routes
  # Then approve routes in Tailscale admin console.
}
