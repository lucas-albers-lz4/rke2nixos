{
  description = "Immutable RKE2 on NixOS — generic flake for x86_64 and aarch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
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
          ];
        };
      };

      mkNixos =
        system: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self sops-nix;
          };
          modules = [
            sops-nix.nixosModules.sops
            nixosModules.default
          ]
          ++ modules;
        };
    in
    {
      inherit nixosModules;

      nixosConfigurations = {
        example-server0 = mkNixos "x86_64-linux" [ ./hosts/example-server0.nix ];
        example-agent0 = mkNixos "x86_64-linux" [ ./hosts/example-agent0.nix ];
        example-server1 = mkNixos "x86_64-linux" [ ./hosts/example-server1.nix ];
        example-server2 = mkNixos "x86_64-linux" [ ./hosts/example-server2.nix ];

        # Same hosts evaluable for aarch64 (QEMU / Pi later)
        example-server0-aarch64 = mkNixos "aarch64-linux" [ ./hosts/example-server0.nix ];
        example-agent0-aarch64 = mkNixos "aarch64-linux" [ ./hosts/example-agent0.nix ];
      };

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

      # Convenience: interactive VMs on a Linux builder
      packages = forAllSystems (
        system: {
          example-server0-vm = self.nixosConfigurations.${
            if system == "aarch64-linux" then "example-server0-aarch64" else "example-server0"
          }.config.system.build.vm;
          example-agent0-vm = self.nixosConfigurations.${
            if system == "aarch64-linux" then "example-agent0-aarch64" else "example-agent0"
          }.config.system.build.vm;
        }
      );
    };
}
