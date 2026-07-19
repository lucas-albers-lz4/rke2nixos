# Proxmox VM profile: virtio disk/NIC, QEMU guest agent, cloud-init ready.
# Pair with hosts/sops-token.nix and a role host under hosts/proxmox/.
{ modulesPath, lib, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/virtualisation/disk-image.nix")
  ];

  image.format = "qcow2";
  image.efiSupport = true;
  virtualisation.diskSize = lib.mkDefault (20 * 1024); # MiB

  # Keep the image closure small so make-disk-image/LKL does not choke on nixpkgs sources.
  nix.channel.enable = false;
  documentation.enable = false;
  documentation.nixos.enable = false;
  system.includeBuildDependencies = false;
  programs.command-not-found.enable = false;

  # Proxmox typically presents virtio SCSI/disk; label-based root matches make-disk-image.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  services.qemuGuest.enable = true;
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  # Prefer DHCP via cloud-init / Proxmox; static overrides go in the host module.
  networking.useDHCP = lib.mkDefault true;
  networking.useNetworkd = lib.mkDefault true;

  services.openssh.enable = true;

  # Images bake without baked-in passwords. Inject SSH keys via cloud-init or the
  # host module before production use (see docs/deploy-proxmox.md).
  users.mutableUsers = true;
  users.allowNoPasswordLogin = true;
  users.users.root.openssh.authorizedKeys.keys = lib.mkDefault [ ];

  system.stateVersion = "25.11";
}
