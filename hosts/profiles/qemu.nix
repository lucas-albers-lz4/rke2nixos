# Shared minimal profile for QEMU / local interactive VMs.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  users.users.root.openssh.authorizedKeys.keys = [ ];
  services.openssh.enable = true;

  # Lab convenience — replace with sops-managed users in real deploys
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
