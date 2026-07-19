# Shared Proxmox deploy settings — edit here before bake / join.
{
  # Break-glass bootstrap / tlsSan when VIP is down. Matches server0 static IP
  # (Campaign 1: one address per CP — no DHCP+secondary dual stack).
  bootstrapHost = "192.168.1.32";

  # Cluster VIP for join/API (keepalived unicast). Do not use .20 on this LAN.
  clusterVip = "192.168.1.29";

  # Static CP addresses (must match ens18 + VRRP unicast peers).
  server0Ip = "192.168.1.32";
  server1Ip = "192.168.1.36";
  server2Ip = "192.168.1.35";

  gateway = "192.168.1.1";

  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjCUGV97GhdCgKFTpu4PzjF0BS/7c8OXbUDsHCoBnzx lalbers@lalbers-X470-AORUS-ULTRA-GAMING"
  ];
}
