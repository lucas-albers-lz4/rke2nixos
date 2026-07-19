# Shared Proxmox deploy settings — edit here before bake / join.
{
  # Sticky bootstrap address for joinUrl + TLS SANs.
  # Proxmox lab (2026-07): server0 = 192.168.1.24, agent0 = 192.168.1.25
  bootstrapHost = "192.168.1.24";

  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjCUGV97GhdCgKFTpu4PzjF0BS/7c8OXbUDsHCoBnzx lalbers@lalbers-X470-AORUS-ULTRA-GAMING"
  ];
}
