{ pkgs, ... }: {
  imports = [
    ../../modules/ser2net
    ../../modules/nut-server
  ];

  # --- ser2net serial consoles ---
  services.lab-ser2net = {
    enable = true;
    connections = {
      riscv1 = {
        port = 3001;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "RISC-V Board 1 (SpacemiT K1)";
      };
      riscv2 = {
        port = 3002;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "RISC-V Board 2";
      };
      arm1 = {
        port = 3003;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "115200n81";
        description = "ARM Board 1";
      };
      server1 = {
        port = 3004;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "9600n81";
        description = "x86 Server 1 (serial console)";
      };
      server2 = {
        port = 3005;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "9600n81";
        description = "x86 Server 2 (serial console)";
      };
      server3 = {
        port = 3006;
        device = "/dev/serial/by-id/REPLACE_WITH_ACTUAL_ID";
        speed = "9600n81";
        description = "x86 Server 3 (serial console)";
      };
    };
  };

  # --- udev rules for persistent serial device names ---
  services.udev.extraRules = ''
    # Populate after running: just discover-serial
    # Example (by FTDI serial number):
    # SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{serial}=="FT6S3FJD", SYMLINK+="serial/riscv1"
    # SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{serial}=="AB0K7UZZ", SYMLINK+="serial/server1"

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
