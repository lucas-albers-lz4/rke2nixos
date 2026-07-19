# Bare-metal template profile.
# Replace disk device, NIC name, and authorized keys before imaging or nixos-install.
{ lib, ... }:
{
  # UEFI by default; switch to grub+BIOS if the machine requires it.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Placeholder root — override in the host module (or swap for disko).
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Optional dedicated volume for mutable RKE2 state across NixOS generations.
  # fileSystems."/var/lib/rancher/rke2" = {
  #   device = "/dev/disk/by-label/rke2-state";
  #   fsType = "ext4";
  # };

  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.eno1.useDHCP = true; # set real NIC name per machine

  services.openssh.enable = true;

  # Set root SSH keys in the host module before first boot (docs/deploy-bare-metal.md).
  users.mutableUsers = true;
  users.allowNoPasswordLogin = true;
  users.users.root.openssh.authorizedKeys.keys = lib.mkDefault [ ];

  system.stateVersion = "25.11";
}
