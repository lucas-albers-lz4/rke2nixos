# Immutable RKE2 on NixOS

Generic flake that wraps upstream nixpkgs [`services.rke2`](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/services/cluster/rancher) for reproducible, multi-arch (x86_64 / aarch64) clusters. NixOS provides the immutable OS; RKE2 state stays mutable under `/var/lib/rancher/rke2`.

## Why this repo exists

nixpkgs already packages RKE2 and ships a full NixOS module (role, token, CNI, CIS, manifests, airgap images). This flake adds:

- Thin role wrappers (`rke2nixos.server` / `rke2nixos.agent`) with bootstrap vs join semantics
- Firewall, sysctl, hostname/`node-name` conventions
- Example hosts for **1 server + 1 agent → 3-server quorum**
- QEMU NixOS tests with preloaded image archives

It does **not** reimplement the RKE2 systemd unit.

## Quick start

Flakes need `nix-command` and `flakes` enabled (via nix.conf, or `--extra-experimental-features 'nix-command flakes'`). Prefer Nix-in-Docker for day-to-day work — see [TODO.md](TODO.md).

```bash
# Requires Nix (Linux builder for VM tests; macOS can evaluate / cross via linux-builder)
# flake.lock is already present after the first nix flake update
nix flake update
nix flake show

# Evaluate example configs
nix build .#nixosConfigurations.example-server0.config.system.build.toplevel

# QEMU checks (Linux only; heavy — downloads RKE2 airgap images; needs KVM)
nix build .#checks.x86_64-linux.server-agent
nix build .#checks.x86_64-linux.single-node
nix build .#checks.x86_64-linux.three-server
```

### Interactive VMs

```bash
nix run .#example-server0-vm
# elsewhere / second terminal after networking is set up:
nix run .#example-agent0-vm
```

Join URL for agents and additional servers is sticky to the bootstrap node: `https://<server0-ip>:9345`.

## Layout

```
flake.nix
modules/
  common.nix           # firewall, sysctl, state dirs
  cluster-defaults.nix # package, CNI (canal), optional image preload
  rke2-server.nix      # bootstrap / joining control-plane
  rke2-agent.nix       # workers
hosts/
  example-server0.nix  # bootstrap CP
  example-agent0.nix   # first agent
  example-server1.nix  # joining CP (HA)
  example-server2.nix  # joining CP (quorum)
tests/                 # nixosTest QEMU suites
secrets/               # sops-nix token scaffold
```

## Bootstrap semantics

| Role | Config | Join |
|------|--------|------|
| Bootstrap server | `rke2nixos.server.bootstrap = true` | initializes cluster |
| Additional server | `bootstrap = false` + `joinUrl` | `https://server0:9345` + shared token |
| Agent | `rke2nixos.agent` | same `joinUrl` + token |

**Token:** generate once, store via sops-nix, reuse forever. Regenerating breaks joins and rebuilds.

**State:** declarative config under `/etc/rancher/rke2` (and Nix); mutable data under `/var/lib/rancher/rke2` (persist across generations; optional dedicated disk).

## Secrets (sops-nix)

1. Install age and put your public key in [`secrets/.sops.yaml`](secrets/.sops.yaml)
2. Encrypt [`secrets/rke2-token.enc.yaml`](secrets/rke2-token.enc.yaml)
3. In a host module:

```nix
sops.defaultSopsFile = ../secrets/rke2-token.enc.yaml;
sops.secrets.rke2-token = { };
rke2nixos.server.tokenFile = config.sops.secrets.rke2-token.path;
```

Example hosts currently seed a lab token via activation script for QEMU convenience — replace with sops for real nodes.

## Growing to 3-server quorum

1. Bring up `example-server0`, then `example-agent0` (or skip agent).
2. Join `example-server1` and `example-server2` with the same token and `joinUrl = "https://server0:9345"`.
3. Confirm three Ready control-plane nodes / etcd members.

### Control-plane rebuild rules

- Remove the etcd member **and** `kubectl delete node` from a **surviving** CP before reinstalling a CP node.
- Rejoin with the **same** cluster token.
- Do not rebuild the last remaining server without an etcd backup/restore plan.
- Join URL stays on `server0` until you introduce a VIP/LB (not in v1).

See also [docs/etcd-rebuild.md](docs/etcd-rebuild.md).

## Firewall

Ports opened by `modules/common.nix` (firewall stays enabled):

- TCP `6443` (API), `9345` (supervisor), `10250` (kubelet), `9099` (Canal)
- TCP `2379`/`2380` on servers (etcd)
- UDP `8472` (Canal VXLAN)

## Phase 2 (deferred)

Not implemented yet — intentional backlog:

- Cilium + `disable-kube-proxy` + HelmChartConfig (see production ansible patterns separately)
- Full airgap module polish beyond `preloadImages`
- Raspberry Pi 4 host profile (`nixos-hardware`)
- `registries.yaml` helper + restart semantics
- Deploy tool choice (nixos-rebuild / deploy-rs / colmena)

## Platform notes

- **CI / containers:** preferred path for reproducible builds is Nix-in-Docker (and later GitHub Actions), not a bare-metal Nix install. Steps live in [TODO.md](TODO.md).
- **Linux KVM (QEMU checks):** builders need `/dev/kvm` (put `nixbld*` in the `kvm` group; set `extra-sandbox-paths = /dev/kvm` in nix.conf). Without KVM, QEMU falls back to TCG and RKE2 tests are impractical.
- **macOS:** flake evaluation works once Nix is installed; `nixosTest` / `build.vm` need a Linux builder (CI, remote, or nix-darwin linux-builder + binfmt for aarch64).
- **CNI:** v1 defaults to **canal**. Cilium is phase 2.
- **Upstream:** bump RKE2 with `nix flake update` (nixpkgs update scripts handle package bumps).

## License

Same as your choice for this repository; RKE2 and nixpkgs retain their upstream licenses.
