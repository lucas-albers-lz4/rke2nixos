# Proxmox lab inventory for rolling upgrades / deploy helpers.
# Checked into git next to hosts (P3: no sibling YAML SoT). Edit when VMs/IPs change.
{
  controlPlanes = [
    {
      config = "proxmox-server0";
      target = "root@192.168.1.32";
      nodeName = "server0";
      bootstrap = true;
    }
    {
      config = "proxmox-server1";
      target = "root@192.168.1.36";
      nodeName = "server1";
      bootstrap = false;
    }
    {
      config = "proxmox-server2";
      target = "root@192.168.1.35";
      nodeName = "server2";
      bootstrap = false;
    }
  ];

  agents = [
    {
      config = "proxmox-agent0";
      # Campaign 3: still DHCP/sticky dual — leave until agent matrix sprint.
      target = "root@192.168.1.25";
      nodeName = "agent0";
    }
  ];
}
