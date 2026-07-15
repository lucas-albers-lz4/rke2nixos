{
  pkgs,
  lib,
}:
let
  t = import ./lib.nix { inherit pkgs lib; };
in
pkgs.testers.runNixOSTest {
  name = "rke2nixos-server-agent";

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
              "agent0"
            ];
          };
        };

        services.rke2.manifests.canal-config.content = t.canalConfig;
      };

    agent0 =
      { config, nodes, ... }:
      {
        imports = t.modules;

        networking.hostName = "agent0";
        networking.firewall.allowedUDPPorts = [ 8472 ];
        networking.firewall.allowedTCPPorts = [ 9099 ];

        virtualisation = t.agentResources.virtualisation;

        rke2nixos = {
          package = t.rke2;
          cni = "canal";
          preloadImages = true;
          agent = {
            enable = true;
            joinUrl = "https://${nodes.server0.networking.primaryIPAddress}:9345";
            tokenFile = t.tokenFile;
            nodeIP = config.networking.primaryIPAddress;
          };
        };
      };
  };

  testScript = ''
    start_all()

    server0.wait_for_unit("rke2-server")
    agent0.wait_for_unit("rke2-agent")

    server0.wait_until_succeeds(r"""${t.kubectl} wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' nodes/agent0""")
    server0.wait_until_succeeds(r"""${t.kubectl} wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' nodes/server0""")

    server0.succeed("${t.kubectl} cluster-info")
    out = server0.succeed("${t.kubectl} get nodes --no-headers | wc -l")
    assert int(out.strip()) == 2, f"expected 2 nodes, got {out}"
  '';
}
