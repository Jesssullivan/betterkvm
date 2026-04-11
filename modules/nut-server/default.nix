{ config, ... }:
{
  # NUT (Network UPS Tools) -- server mode
  # Monitors a USB-attached UPS and serves status to other nodes

  power.ups = {
    enable = true;
    mode = "netserver"; # Serve UPS data to other lab nodes

    ups."rack-ups" = {
      description = "Lab Rack UPS";
      driver = "usbhid-ups"; # Works with APC, CyberPower, etc.
      port = "auto";
      directives = [
        "offdelay = 120"
        "ondelay = 60"
      ];
    };

    upsd.listen = [
      {
        address = "0.0.0.0";
        port = 3493;
      }
    ];

    # NUT auth user for monitoring
    users.upsmon = {
      passwordFile = config.sops.secrets.nut-password.path;
      upsmon = "primary";
    };

    upsmon = {
      enable = true;
      monitor."rack-ups@localhost" = {
        powerValue = 1;
        type = "primary";
        user = "upsmon";
        passwordFile = config.sops.secrets.nut-password.path;
      };
      settings = {
        MINSUPPLIES = 1;
        SHUTDOWNCMD = "/run/current-system/sw/bin/shutdown -h +0";
        POLLFREQ = 5;
        POLLFREQALERT = 2;
        FINALDELAY = 5;
      };
    };

    openFirewall = true;
  };
}
