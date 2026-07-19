# Shared Proxmox deploy settings — edit here before bake / join.
{
  # Sticky bootstrap address for joinUrl + TLS SANs (until VIP is active).
  # Proxmox lab (2026-07): server0 = 192.168.1.24, agent0 = 192.168.1.25
  # server1/server2 currently on DHCP .36/.35 (L7/L8); reserve sticky IPs when convenient.
  bootstrapHost = "192.168.1.24";

  # Cluster VIP for join/API (keepalived on CPs). Empty = sticky bootstrapHost only.
  clusterVip = "192.168.1.29";

  # Node addresses used for VRRP unicast peers (must match ens18 on each CP).
  # server0 primary DHCP is .32; sticky .24 is secondary on the same NIC.
  server0Ip = "192.168.1.32";
  server1Ip = "192.168.1.36";
  server2Ip = "192.168.1.35";

  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjCUGV97GhdCgKFTpu4PzjF0BS/7c8OXbUDsHCoBnzx lalbers@lalbers-X470-AORUS-ULTRA-GAMING"
  ];
}
