{ pkgs, ... }: {
  imports = [
    ../../modules/ser2net
    ../../modules/nut-server
  ];

  # --- ser2net serial consoles (16 ports) ---
  services.lab-ser2net = {
    enable = true;
    connections = {
      honey = {
        port = 3001;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 1: honey";
      };
      bumble = {
        port = 3002;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 2: bumble";
      };
      petting-zoo-mini = {
        port = 3003;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 3: petting-zoo-mini";
      };
      xoxd-bates = {
        port = 3004;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 4: xoxd-bates";
      };
      yoga = {
        port = 3005;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 5: yoga";
      };
      mbp-13 = {
        port = 3006;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 6: mbp-13";
      };
      betsy = {
        port = 3007;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 7: betsy";
      };
      musey = {
        port = 3008;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 8: musey";
      };
      sdr-1 = {
        port = 3009;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 9: sdr-1";
      };
      g2-1 = {
        port = 3010;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 10: g2-1";
      };
      g2-2 = {
        port = 3011;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 11: g2-2";
      };
      t-deck = {
        port = 3012;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 12: t-deck";
      };
      tdeck-pro = {
        port = 3013;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 13: tdeck-pro";
      };
      port14 = {
        port = 3014;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 14: (unassigned)";
      };
      port15 = {
        port = 3015;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 15: (unassigned)";
      };
      port16 = {
        port = 3016;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "Port 16: (unassigned)";
      };
    };
  };

  # --- udev rules for persistent serial device names ---
  services.udev.extraRules = ''
    # Populate after running: just discover-serial
    # Example (by FTDI serial number):
    # SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{serial}=="FT6S3FJD", SYMLINK+="serial/honey"
    # SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{serial}=="AB0K7UZZ", SYMLINK+="serial/bumble"

    # Example (by USB port path, for CH340 without serial numbers):
    # SUBSYSTEM=="tty", ATTRS{devpath}=="1.3.1", SYMLINK+="serial/port1"
  '';

  # --- Tailscale subnet router ---
  # Advertise lab management network to tailnet
  # After boot: tailscale set --advertise-routes=10.0.0.0/24
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Additional packages for this host
  environment.systemPackages = with pkgs; [
    picocom    # Interactive serial terminal
    minicom    # Alternative serial terminal
    inetutils  # telnet client for testing ser2net
  ];
}
