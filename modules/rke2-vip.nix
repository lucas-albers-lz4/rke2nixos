# Optional VRRP VIP for RKE2 join / API (Phase B bridge).
# Enable on control-plane hosts via rke2nixos.vip.enable + virtualIp.
# Prefer unicastPeers when CPs span Proxmox nodes (multicast often blocked).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rke2nixos.vip;
in
{
  options.rke2nixos.vip = {
    enable = lib.mkEnableOption "keepalived VRRP VIP for cluster join/API (flake-declared)";

    virtualIp = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "192.168.1.20";
      description = "Cluster VIP address (must be free on the LAN).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "ens18";
      description = "Interface that carries the VIP (Proxmox virtio NIC is typically ens18).";
    };

    virtualRouterId = lib.mkOption {
      type = lib.types.ints.between 1 255;
      default = 51;
      description = "VRRP virtual_router_id — unique on the L2 segment.";
    };

    priority = lib.mkOption {
      type = lib.types.ints.between 1 255;
      default = 100;
      description = "VRRP priority; higher wins. Bootstrap CP should be highest.";
    };

    authPass = lib.mkOption {
      type = lib.types.str;
      default = "rke2nixo"; # max 8 chars for keepalived PASS
      description = "VRRP auth_pass (max 8 chars for keepalived PASS). Lab default only.";
    };

    unicastSrcIp = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "This node's address for unicast VRRP (required with unicastPeers).";
    };

    unicastPeers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Other CP node IPs for unicast VRRP (use when multicast is unreliable across hypervisors).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.rke2nixos.server.enable;
        message = "rke2nixos.vip: only enable on control-plane (server) hosts";
      }
      {
        assertion = cfg.virtualIp != "";
        message = "rke2nixos.vip: set virtualIp (usually settings.clusterVip)";
      }
    ];

    environment.systemPackages = [ pkgs.keepalived ];

    services.keepalived = {
      enable = true;
      openFirewall = true;
      vrrpInstances.rke2nixos = {
        interface = cfg.interface;
        virtualRouterId = cfg.virtualRouterId;
        priority = cfg.priority;
        state = if cfg.priority >= 150 then "MASTER" else "BACKUP";
        unicastSrcIp = cfg.unicastSrcIp;
        unicastPeers = cfg.unicastPeers;
        virtualIps = [
          {
            addr = "${cfg.virtualIp}/24";
          }
        ];
        extraConfig = ''
          authentication {
            auth_type PASS
            auth_pass ${cfg.authPass}
          }
          advert_int 1
        '';
      };
    };
  };
}
