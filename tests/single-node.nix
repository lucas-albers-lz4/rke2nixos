{
  pkgs,
  lib,
}:
let
  t = import ./lib.nix { inherit pkgs lib; };
in
pkgs.testers.runNixOSTest {
  name = "rke2nixos-single-node";

  nodes.server0 =
    { config, ... }:
    {
      imports = t.modules;

      networking.hostName = "server0";
      networking.firewall.allowedUDPPorts = [ 8472 ];
      networking.firewall.allowedTCPPorts = [
        6443
        9099
        9345
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
          tlsSans = [ "server0" ];
        };
      };

      services.rke2.manifests.canal-config.content = t.canalConfig;
    };

  testScript = ''
    start_all()
    server0.wait_for_unit("rke2-server")
    server0.wait_until_succeeds(r"""${t.kubectl} wait --for='jsonpath={.status.conditions[?(@.type=="Ready")].status}=True' nodes/server0""")
    server0.succeed("${t.kubectl} cluster-info")
    server0.wait_until_succeeds("${t.kubectl} get serviceaccount default")
  '';
}
