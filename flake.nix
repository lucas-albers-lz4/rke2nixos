{
  description = "Immutable RKE2 on NixOS — generic flake for x86_64 and aarch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # RKE2 pin (P4): bump independently via `nix flake lock --update-input nixpkgs-rke2`.
    # Initially may share the same rev as nixpkgs; do not `follows` nixpkgs.
    nixpkgs-rke2.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-rke2,
      sops-nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = lib.genAttrs systems;

      mkPkgs = system: import nixpkgs { inherit system; };
      mkRke2Pkgs = system: import nixpkgs-rke2 { inherit system; };

      nixosModules = {
        common = ./modules/common.nix;
        cluster-defaults = ./modules/cluster-defaults.nix;
        rke2-server = ./modules/rke2-server.nix;
        rke2-agent = ./modules/rke2-agent.nix;
        default = {
          imports = [
            ./modules/common.nix
            ./modules/cluster-defaults.nix
            ./modules/rke2-server.nix
            ./modules/rke2-agent.nix
            ./modules/rke2-vip.nix
          ];
        };
      };

      mkNixos =
        system: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self sops-nix;
            rke2Pkgs = mkRke2Pkgs system;
          };
          modules = [
            sops-nix.nixosModules.sops
            nixosModules.default
          ]
          ++ modules;
        };

      # Proxmox lab: one topology file → nixosConfigurations + qcow2 packages.
      proxmoxTopology = import ./hosts/proxmox/topology.nix;
      proxmoxMkHost = import ./hosts/proxmox/mk-host.nix;
      proxmoxConfigurations = lib.listToAttrs (
        map (
          node:
          lib.nameValuePair "proxmox-${node.name}" (
            mkNixos "x86_64-linux" [ (proxmoxMkHost proxmoxTopology node) ]
          )
        ) proxmoxTopology.nodes
      );
    in
    {
      inherit nixosModules;

      nixosConfigurations = {
        # QEMU / CI lab hosts (lab token)
        example-server0 = mkNixos "x86_64-linux" [ ./hosts/example-server0.nix ];
        example-agent0 = mkNixos "x86_64-linux" [ ./hosts/example-agent0.nix ];
        example-server1 = mkNixos "x86_64-linux" [ ./hosts/example-server1.nix ];
        example-server2 = mkNixos "x86_64-linux" [ ./hosts/example-server2.nix ];

        example-server0-aarch64 = mkNixos "aarch64-linux" [ ./hosts/example-server0.nix ];
        example-agent0-aarch64 = mkNixos "aarch64-linux" [ ./hosts/example-agent0.nix ];

        # Bare-metal deploy hosts (sops token)
        bare-metal-server0 = mkNixos "x86_64-linux" [ ./hosts/bare-metal/server0.nix ];
        bare-metal-agent0 = mkNixos "x86_64-linux" [ ./hosts/bare-metal/agent0.nix ];

        # Installer ISO (nixos-install onto bare metal)
        installer-iso = mkNixos "x86_64-linux" [ ./hosts/profiles/iso.nix ];
      }
      // proxmoxConfigurations;

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          single-node = import ./tests/single-node.nix { inherit pkgs lib; };
          server-agent = import ./tests/server-agent.nix { inherit pkgs lib; };
          three-server = import ./tests/three-server.nix { inherit pkgs lib; };
        }
      );

      formatter = forAllSystems (system: (mkPkgs system).nixfmt-rfc-style);

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          serverName = if system == "aarch64-linux" then "example-server0-aarch64" else "example-server0";
          agentName = if system == "aarch64-linux" then "example-agent0-aarch64" else "example-agent0";
          installer = self.nixosConfigurations.installer-iso;
          proxmoxQcow2 = lib.listToAttrs (
            map (
              node:
              lib.nameValuePair "proxmox-${node.name}-qcow2" (
                self.nixosConfigurations."proxmox-${node.name}".config.system.build.image
              )
            ) proxmoxTopology.nodes
          );
        in
        {
          example-server0 = self.nixosConfigurations.${serverName}.config.system.build.toplevel;
          example-agent0 = self.nixosConfigurations.${agentName}.config.system.build.toplevel;
          example-server0-vm = self.nixosConfigurations.${serverName}.config.system.build.vm;
          example-agent0-vm = self.nixosConfigurations.${agentName}.config.system.build.vm;
        }
        // lib.optionalAttrs (system == "x86_64-linux") (
          proxmoxQcow2
          // {
            installer-iso = installer.config.system.build.isoImage;
          }
        )
      );

      # Day-2: nixos-rebuild wrappers live in scripts/; apps expose common entry points.
      apps = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          mkApp = program: {
            type = "app";
            program = "${pkgs.writeShellScript "app" program}";
          };
        in
        {
          deploy-local = mkApp ''
            set -euo pipefail
            host="''${1:?usage: nix run .#deploy-local -- <nixosConfiguration>}"
            exec nixos-rebuild switch --flake "${self}#$host"
          '';
        }
      );
    };
}
