{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.lab-ser2net;

  # Generate ser2net YAML from Nix attrset
  connectionYaml = name: conn: ''
    connection: &${name}
      accepter: tcp,${toString conn.port}
      connector: serialdev,${conn.device},${conn.speed},local
      options:
        banner: "=== ${conn.description} ===\r\n"
        kickolduser: true
  '';

  ser2netConfig = pkgs.writeText "ser2net.yaml" ''
    %YAML 1.1
    ---
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList connectionYaml cfg.connections)}
  '';
in
{
  options.services.lab-ser2net = {
    enable = lib.mkEnableOption "lab serial console server (ser2net)";

    connections = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port to listen on";
            };
            device = lib.mkOption {
              type = lib.types.str;
              description = "Serial device path (use /dev/serial/by-id/... for stability)";
            };
            speed = lib.mkOption {
              type = lib.types.str;
              default = "115200n81";
              description = "Serial port settings (speed, parity, data bits, stop bits)";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Human-readable name shown in banner";
            };
          };
        }
      );
      default = { };
      description = "Serial console connections to expose over TCP";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.ser2net ];

    environment.etc."ser2net/ser2net.yaml".source = ser2netConfig;

    systemd.services.ser2net = {
      description = "Serial to Network Proxy";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.ser2net}/bin/ser2net -n -c /etc/ser2net/ser2net.yaml";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Open firewall ports for each connection
    networking.firewall.allowedTCPPorts = lib.mapAttrsToList (_: conn: conn.port) cfg.connections;
  };
}
