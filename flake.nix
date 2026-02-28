{
  description = "Multiarch KVM Lab - Raspberry Pi fleet management";

  # Attic binary cache — CI pushes all derivations here.
  # Local builds automatically pull cached artifacts from CI.
  nixConfig = {
    extra-substituters = [ "https://nix-cache.fuzzy-dev.tinyland.dev/main" ];
    extra-trusted-public-keys = [ "main:NKRk1XYo/dfd9fcDqgotUJg2DTDHWp5ny+Ba7WzRjgE=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, deploy-rs, sops-nix }:
  let
    # Helper to create a Pi 4 NixOS configuration
    mkPiSystem = { hostname, modules }: nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit self nixpkgs-unstable; };
      modules = [
        # SD card image support
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

        # Raspberry Pi 4 hardware support
        nixos-hardware.nixosModules.raspberry-pi-4

        # Secrets management
        sops-nix.nixosModules.sops

        # Shared modules
        ./hosts/common/base.nix
        ./hosts/common/users.nix
        ./hosts/common/tailscale.nix
        ./hosts/common/networking.nix

        # Host identity
        { networking.hostName = hostname; }
      ] ++ modules;
    };
  in {
    # -- NixOS Configurations --
    nixosConfigurations = {
      serial-console = mkPiSystem {
        hostname = "serial-console";
        modules = [
          ./hosts/serial-console/default.nix
        ];
      };

      # Uncomment when adding a third Pi:
      # monitor-node = mkPiSystem {
      #   hostname = "monitor-node";
      #   modules = [
      #     ./hosts/monitor-node/default.nix
      #   ];
      # };
    };

    # -- SD Card Images --
    # Build: nix build .#images.serial-console
    images = {
      serial-console =
        self.nixosConfigurations.serial-console.config.system.build.sdImage;
    };

    # -- Custom Packages --
    packages.x86_64-linux = {
      tesmart-ctl = nixpkgs.legacyPackages.x86_64-linux.callPackage ./packages/tesmart-ctl {};
    };
    packages.aarch64-linux = {
      tesmart-ctl = nixpkgs.legacyPackages.aarch64-linux.callPackage ./packages/tesmart-ctl {};
    };

    # -- deploy-rs Configuration --
    deploy.nodes = {
      serial-console = {
        hostname = "serial-console"; # Tailscale MagicDNS or IP
        profiles.system = {
          user = "root";
          sshUser = "root";
          path = deploy-rs.lib.aarch64-linux.activate.nixos
            self.nixosConfigurations.serial-console;
        };
        fastConnection = false; # Build locally, copy to Pi
        autoRollback = true;
        magicRollback = true;
      };
    };

    # -- Flake Checks (deploy-rs rollback verification) --
    checks = builtins.mapAttrs
      (system: deployLib: deployLib.deployChecks self.deploy)
      deploy-rs.lib;

    # -- Dev Shell --
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
        just
        python3
        deploy-rs.packages.x86_64-linux.default
        sops
        age
        ssh-to-age
        nixos-rebuild
        zstd
        gh
      ];
    };
  };
}
