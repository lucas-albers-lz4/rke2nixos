# Shared helpers for QEMU NixOS tests (canal on eth1, airgap images).
{
  pkgs,
  lib,
  rke2 ? pkgs.rke2,
}:
let
  throwSystem = throw "rke2nixos tests: unsupported system ${pkgs.stdenv.hostPlatform.system}";
  system = pkgs.stdenv.hostPlatform.system;
in
rec {
  inherit rke2;

  tokenFile = pkgs.writeText "rke2-token" "test-cluster-token";

  coreImages =
    {
      aarch64-linux = rke2.images-core-linux-arm64-tar-zst;
      x86_64-linux = rke2.images-core-linux-amd64-tar-zst;
    }
    .${system} or throwSystem;

  canalImages =
    {
      aarch64-linux = rke2.images-canal-linux-arm64-tar-zst;
      x86_64-linux = rke2.images-canal-linux-amd64-tar-zst;
    }
    .${system} or throwSystem;

  # Let flannel/canal use eth1 for inter-node communication in the test driver.
  canalConfig = {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChartConfig";
    metadata = {
      name = "rke2-canal";
      namespace = "kube-system";
    };
    spec.valuesContent = builtins.toJSON {
      flannel.iface = "eth1";
    };
  };

  modules = [
    ../modules/common.nix
    ../modules/cluster-defaults.nix
    ../modules/rke2-server.nix
    ../modules/rke2-agent.nix
  ];

  serverResources = {
    virtualisation.cores = 2;
    virtualisation.memorySize = 4096;
    virtualisation.diskSize = 8192;
  };

  agentResources = {
    virtualisation.cores = 2;
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 8192;
  };

  testDisable = [
    "rke2-coredns"
    "rke2-metrics-server"
    "rke2-ingress-nginx"
    "rke2-snapshot-controller"
    "rke2-snapshot-controller-crd"
    "rke2-snapshot-validation-webhook"
  ];

  kubectl = "${pkgs.kubectl}/bin/kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml";
}
