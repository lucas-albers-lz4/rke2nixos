# Three-server quorum smoke test (phase 1.5).
# etcd becomes HA once three control-plane members are Ready.
{
  pkgs,
  lib,
}:
let
  t = import ./lib.nix { inherit pkgs lib; };

  mkJoiningServer =
    name:
    {
      config,
      nodes,
      ...
    }:
    {
      imports = t.modules;

      networking.hostName = name;
      networking.firewall.allowedUDPPorts = [ 8472 ];
      networking.firewall.allowedTCPPorts = [
        6443
        9099
        9345
        2379
        2380
      ];

      virtualisation = t.serverResources.virtualisation;

      rke2nixos = {
        package = t.rke2;
        cni = "canal";
        preloadImages = true;
        disable = t.testDisable;
        server = {
          enable = true;
          bootstrap = false;
          joinUrl = "https://${nodes.server0.networking.primaryIPAddress}:9345";
          tokenFile = t.tokenFile;
          nodeIP = config.networking.primaryIPAddress;
          tlsSans = [
            "server0"
            "server1"
            "server2"
          ];
        };
      };

      services.rke2.manifests.canal-config.content = t.canalConfig;
    };
in
pkgs.testers.runNixOSTest {
  name = "rke2nixos-three-server";

  nodes = {
    server0 =
      { config, ... }:
      {
        imports = t.modules;

        networking.hostName = "server0";
        networking.firewall.allowedUDPPorts = [ 8472 ];
        networking.firewall.allowedTCPPorts = [
          6443
          9099
          9345
          2379
          2380
        ];

        virtualisation = t.serverResources.virtualisation;

        rke2nixos = {
          package = t.rke2;
          cni = "canal";
          preloadImages = true;
          disable = t.testDisable;
          server = {
            enable = true;
            bootstrap = true;
            tokenFile = t.tokenFile;
            nodeIP = config.networking.primaryIPAddress;
            tlsSans = [
              "server0"
              "server1"
              "server2"
            ];
          };
        };

        services.rke2.manifests.canal-config.content = t.canalConfig;
      };

    server1 = mkJoiningServer "server1";
    server2 = mkJoiningServer "server2";
  };

  testScript = ''
    start_all()

    server0.wait_for_unit("rke2-server")
    server1.wait_for_unit("rke2-server")
    server2.wait_for_unit("rke2-server")

    for node in ["server0", "server1", "server2"]:
        server0.wait_until_succeeds(
            rf"""${t.kubectl} wait --for='jsonpath={{.status.conditions[?(@.type=="Ready")].status}}=True' nodes/{node}"""
        )

    out = server0.succeed("${t.kubectl} get nodes --no-headers | wc -l")
    assert int(out.strip()) == 3, f"expected 3 control-plane nodes, got {out}"

    # Embedded etcd should report three members once quorum is formed.
    server0.wait_until_succeeds(
        "${t.kubectl} get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l | grep -q '^3$'"
    )
  '';
}
