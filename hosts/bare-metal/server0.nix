# Bare-metal bootstrap control-plane.
# Before first boot: set disk/NIC overrides and root SSH keys in this file or a sibling.
{ config, ... }:
{
  imports = [
    ../profiles/bare-metal.nix
    ../sops-token.nix
  ];

  networking.hostName = "server0";

  # users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  # networking.interfaces.eno1.ipv4.addresses = [{ address = "10.0.0.10"; prefixLength = 24; }];
  # networking.defaultGateway = "10.0.0.1";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = true;
      tokenFile = config.sops.secrets.rke2-token.path;
      tlsSans = [
        "server0"
      ];
    };
  };
}
