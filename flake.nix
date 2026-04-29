{
  description = "Multiarch KVM Lab - Raspberry Pi fleet management";

  # Attic binary cache — CI pushes all derivations here.
  # Local builds automatically pull cached artifacts from CI.
  # Attic is behind Tailscale; substituter is best-effort (fails open).
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
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixos-hardware,
      deploy-rs,
      sops-nix,
    }:
    let
      # Helper to create a Pi 4 NixOS configuration
      mkPiSystem =
        { hostname, modules }:
        nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit self nixpkgs-unstable; };
          modules = [
            # SD card image support
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

            # Raspberry Pi 4 hardware support
            nixos-hardware.nixosModules.raspberry-pi-4

            # Secrets management
            sops-nix.nixosModules.sops
            { sops.package = sops-nix.packages.aarch64-linux.sops-install-secrets; }

            # Shared modules
            ./hosts/common/base.nix
            ./hosts/common/users.nix
            ./hosts/common/tailscale.nix
            ./hosts/common/networking.nix
            ./hosts/common/secrets.nix

            # Host identity
            { networking.hostName = hostname; }
          ]
          ++ modules;
        };
    in
    {
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
        serial-console = self.nixosConfigurations.serial-console.config.system.build.sdImage;
      };

      # -- Custom Packages --
      packages.x86_64-linux = {
        tesmart-ctl = nixpkgs.legacyPackages.x86_64-linux.callPackage ./packages/tesmart-ctl { };
      };
      packages.aarch64-linux = {
        tesmart-ctl = nixpkgs.legacyPackages.aarch64-linux.callPackage ./packages/tesmart-ctl { };
      };

      # -- deploy-rs Configuration --
      deploy.nodes = {
        serial-console = {
          hostname = "serial-console"; # Tailscale MagicDNS or IP
          profiles.system = {
            user = "root";
            sshUser = "root";
            path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.serial-console;
          };
          fastConnection = false; # Build locally, copy to Pi
          autoRollback = true;
          magicRollback = true;
        };
      };

      # -- Flake Checks --
      checks =
        let
          deployChecks = builtins.mapAttrs (
            _system: deployLib: deployLib.deployChecks self.deploy
          ) deploy-rs.lib;

          customChecks =
            let
              forSystem =
                system:
                let
                  pkgs = nixpkgs.legacyPackages.${system};
                  pythonWithPkgs = pkgs.python3.withPackages (ps: [
                    ps.pytest
                    ps.hypothesis
                    ps.pyyaml
                    ps.setuptools
                  ]);
                in
                {
                  pbt-tesmart-protocol =
                    pkgs.runCommand "pbt-tesmart-protocol" { buildInputs = [ pythonWithPkgs ]; }
                      ''
                        mkdir -p $TMPDIR/work
                        cp -r --no-preserve=mode ${self}/packages/tesmart-ctl/* $TMPDIR/work/
                        cp -r --no-preserve=mode ${self}/mcp $TMPDIR/work/mcp
                        cp -r --no-preserve=mode ${self}/tests $TMPDIR/work/tests
                        cp -r --no-preserve=mode ${self}/hosts $TMPDIR/work/hosts
                        cp --no-preserve=mode ${self}/pyproject.toml $TMPDIR/work/
                        cd $TMPDIR/work
                        ${pythonWithPkgs}/bin/python -m pytest tests/ -v --tb=short -o "addopts="
                        touch $out
                      '';

                  shellcheck-scripts = pkgs.runCommand "shellcheck-scripts" { buildInputs = [ pkgs.shellcheck ]; } ''
                    shellcheck --shell=bash ${self}/scripts/*.sh || true
                    shellcheck --shell=bash ${self}/hosts/pikvm-primary/preseed/pikvm-scripts.d/*.sh
                    touch $out
                  '';

                  tesmart-ctl-build =
                    self.packages.${system}.tesmart-ctl
                      or (pkgs.runCommand "tesmart-ctl-skip" { } "echo 'skipped on ${system}'; touch $out");
                };
            in
            {
              x86_64-linux = forSystem "x86_64-linux";
              aarch64-linux = forSystem "aarch64-linux";
              aarch64-darwin = forSystem "aarch64-darwin";
              x86_64-darwin = forSystem "x86_64-darwin";
            };
        in
        builtins.mapAttrs (
          system: deployCheck: deployCheck // (customChecks.${system} or { })
        ) deployChecks;

      # -- Dev Shell --
      devShells =
        let
          mkPythonWithPkgs =
            pkgs:
            pkgs.python3.withPackages (ps: [
              ps.pytest
              ps.pytest-cov
              ps.hypothesis
              ps.pyyaml
              ps.setuptools
            ]);

          mkTestShell =
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            pkgs.mkShell {
              buildInputs = [
                (mkPythonWithPkgs pkgs)
              ];
            };

          mkDevShell =
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
              pythonWithPkgs = mkPythonWithPkgs pkgs;
            in
            pkgs.mkShell {
              buildInputs =
                with pkgs;
                [
                  just
                  pythonWithPkgs
                  sops
                  age
                  ssh-to-age
                  zstd
                  gh
                  mkpasswd
                ]
                ++ pkgs.lib.optionals (system == "x86_64-linux") [
                  deploy-rs.packages.${system}.default
                  pkgs.nixos-rebuild
                ];
            };
        in
        {
          x86_64-linux = {
            default = mkDevShell "x86_64-linux";
            test = mkTestShell "x86_64-linux";
          };
          aarch64-linux = {
            default = mkDevShell "aarch64-linux";
            test = mkTestShell "aarch64-linux";
          };
          aarch64-darwin = {
            default = mkDevShell "aarch64-darwin";
            test = mkTestShell "aarch64-darwin";
          };
          x86_64-darwin = {
            default = mkDevShell "x86_64-darwin";
            test = mkTestShell "x86_64-darwin";
          };
        };
    };
}
