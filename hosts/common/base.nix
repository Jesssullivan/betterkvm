{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  hardware.enableRedistributableFirmware = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Performance: zram swap for limited Pi RAM
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # System packages available on all Pis
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    usbutils
    pciutils
    lsof
    libraspberrypi
  ];

  time.timeZone = "America/New_York";

  system.stateVersion = "24.11";
}
