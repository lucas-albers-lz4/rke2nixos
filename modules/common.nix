{
  config,
  lib,
  ...
}:
let
  cfg = config.rke2nixos;
  isServer = cfg.server.enable;
  isAgent = cfg.agent.enable;
  enabled = isServer || isAgent;
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !(isServer && isAgent);
        message = "rke2nixos: enable either rke2nixos.server or rke2nixos.agent, not both";
      }
      {
        assertion = config.networking.hostName == lib.toLower config.networking.hostName;
        message = ''
          rke2nixos: networking.hostName must be lowercase so it matches the RKE2 node name.
          Mismatched casing creates duplicate nodes on rebuild.
        '';
      }
    ];

    # RKE2 / Kubernetes required ports. Do not disable the firewall.
    networking.firewall = {
      allowedTCPPorts = lib.mkMerge [
        [
          6443 # Kubernetes API
          9345 # RKE2 supervisor (join)
          10250 # kubelet
        ]
        (lib.optionals isServer [
          2379 # etcd client
          2380 # etcd peer
        ])
        [
          9099 # Canal health
        ]
      ];
      allowedUDPPorts = [
        8472 # Canal / Flannel VXLAN
      ];
    };

    # CIS-oriented / RKE2-friendly defaults (also set by upstream services.rke2)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "vm.swappiness" = 0;
    };

    # State lives here and must survive reboot / NixOS generations.
    # The system closure is immutable; this directory is the mutable concession.
    # Optional: put /var/lib/rancher/rke2 on a dedicated volume or disk.
    systemd.tmpfiles.rules = [
      "d /var/lib/rancher/rke2 0755 root root -"
      "d /etc/rancher/rke2 0700 root root -"
    ];
  };
}
