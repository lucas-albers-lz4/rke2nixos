# ISO installer profile (bare-metal install path).
# Builds config.system.build.isoImage; not a running node config by itself.
{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Keep the installer lean; RKE2 nodes are imaged via nixos-install from this ISO
  # or by flashing a pre-baked disk image.
  isoImage.edition = "rke2nixos";
  isoImage.squashfsCompression = "zstd";
}
