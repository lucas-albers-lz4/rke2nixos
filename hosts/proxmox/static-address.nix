# Static IPv4 on ens18 for Proxmox CPs — one address, no DHCP float.
# Filename sorts before cloud-init's 10-cloud-init-*.network so networkd picks us.
{
  lib,
  address,
  gateway ? "192.168.1.1",
  dns ? [ "192.168.1.1" ],
  interface ? "ens18",
}:
{
  networking.useDHCP = false;
  networking.useNetworkd = true;
  # Do not let cloud-init keep rewriting .network drop-ins.
  services.cloud-init.network.enable = lib.mkForce false;

  # Lexical order: 00-* beats 10-cloud-init-* / 10-sticky / 99-*.
  systemd.network.networks."00-${interface}-static" = {
    matchConfig.Name = interface;
    linkConfig.RequiredForOnline = "routable";
    networkConfig = {
      Address = "${address}/24";
      Gateway = gateway;
      DNS = dns;
      DHCP = "no";
    };
    # Prefer our static config if anything else still matches.
    dhcpV4Config = { };
  };

  # Drop stale cloud-init / sticky drop-ins left from first boot (they persist in /etc).
  system.activationScripts.rke2nixosClearCloudInitNet = {
    text = ''
      rm -f /etc/systemd/network/10-cloud-init-*.network
      rm -f /etc/systemd/network/10-sticky.network
      rm -f /run/systemd/network/10-cloud-init-*.network
    '';
    deps = [ ];
  };
}
