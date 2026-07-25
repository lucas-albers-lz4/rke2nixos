# Getting started (your Proxmox cluster)

Stand up **1 control-plane + 1 agent** on *your* Proxmox using this flake. This path uses **named hosts** from [`hosts/proxmox/topology.nix`](../hosts/proxmox/topology.nix) (static IPs via Nix). Golden clone workers are optional later — see [golden-agent.md](golden-agent.md).

Contributors testing on the reference fleet: see [lab.md](lab.md) (do not replace the live lab topology unless you mean to).

## Prerequisites

- [ ] Workstation with Docker **or** Nix (`nix-command` + `flakes`)
- [ ] Proxmox cluster you can create VMs on
- [ ] Least-privilege API token — [proxmox-rbac.md](proxmox-rbac.md) (`./scripts/proxmox-create-deploy-role.sh` once as root)
- [ ] `genisoimage`, `mkisofs`, `xorriso`, or `cloud-localds` (for age cidata ISO)
- [ ] Free static IPv4s for server, agent, and (recommended) a cluster VIP
- [ ] Your SSH public key for `root` on the guests

## 1. Scaffold secrets (+ topology if needed)

```bash
git clone https://github.com/lucas-albers-lz4/rke2nixos.git
cd rke2nixos

# Creates age key + encrypted cluster token. Does NOT overwrite an existing topology.nix.
./scripts/init-cluster.sh

# Fork / clean personal cluster: start from the example (backs up topology.nix first):
# ./scripts/init-cluster.sh --from-example \
#   --ssh-key 'ssh-ed25519 AAAA… you@laptop' \
#   --gateway 192.168.10.1 \
#   --vip 192.168.10.29 \
#   --bootstrap-ip 192.168.10.10 \
#   --agent-ip 192.168.10.20
```

Edit [`hosts/proxmox/topology.nix`](../hosts/proxmox/topology.nix) until these are correct for **your** LAN:

| Field | Meaning |
|-------|---------|
| `adminSshKeys` | Root SSH public keys |
| `gateway` | Default route |
| `clusterVip` | Keepalived VIP for join/API (or `""` to disable VIP) |
| `nodes[].ip` | Static address per node (`static-address.nix`) |
| `bootstrap = true` | Exactly one server |

Schema reference: [`hosts/proxmox/topology.example.nix`](../hosts/proxmox/topology.example.nix).

## 2. Bake images

Prefer Nix-in-Docker if the host lacks flakes. Qcow2 bake needs KVM:

```bash
# Host Nix:
nix build .#packages.x86_64-linux.proxmox-server0-qcow2 --out-link result-server-qcow
nix build .#packages.x86_64-linux.proxmox-agent0-qcow2 --out-link result-agent-qcow

# Or Docker Nix (copy out in the same run — container store is ephemeral):
# NIX_DOCKER_EXTRA_ARGS='--device /dev/kvm' ./scripts/nix-docker.sh bash -lc '…'
```

## 3. Import VMs

Source your Proxmox env (`PROXMOX_ENV=…` or one of the paths listed in `proxmox-import.sh`). Use **free** VMIDs.

```bash
# Control-plane: ≥3072 MiB. cpu=host is set by the import script (required for canal/RKE2).
PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh ./result-server-qcow/nixos.qcow2 200 local-lvm rke2nixos-server0
./scripts/proxmox-import.sh ./result-agent-qcow/nixos.qcow2 201 local-lvm rke2nixos-agent0
```

Do **not** use Proxmox default `kvm64` — images need x86-64-v2.

## 4. Age key before first boot

sops-nix expects `/var/lib/sops-nix/key.txt` from `secrets/age.key`. **Never bake the key into the qcow2.**

Named hosts get networking from Nix (`static-address.nix`). Attach age cidata only:

```bash
./scripts/proxmox-age-cloudinit.sh 200 201
```

Attach **before** first start (or stop + cold boot after attach).

> **Golden clones (later):** those images keep cloud-init networking; `PROXMOX_IPCONFIG_*` is embedded as nocloud `network-config` in the age ISO. See [golden-agent.md](golden-agent.md). Do not confuse that path with named 1+1 hosts.

## 5. Bring-up order

1. Start **server0**; wait for SSH, `rke2-server` active, and `/run/secrets/rke2-token` (proves age + sops).
2. Start **agent0**; it joins via VIP (or bootstrap IP) from topology.
3. On server0:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes
/var/lib/rancher/rke2/bin/kubectl get pods -A
```

## Success checklist

- [ ] `secrets/age.key` exists; guests have non-empty `/var/lib/sops-nix/key.txt`
- [ ] Topology IPs/SSH keys/VIP match the LAN you actually use
- [ ] Control-plane VM ≥ **3 GiB** RAM; import used `cpu=host`
- [ ] Age cidata attached **before** first boot
- [ ] server0 + agent0 **Ready**; Canal pods not CrashLoop
- [ ] Join URL reachable (`clusterVip:9345` or bootstrap IP)

## Day-2 and HA

- Updates: [day2-updates.md](day2-updates.md), `./scripts/deploy-host.sh`, `./scripts/rolling-upgrade.sh`
- More control planes / etcd replace: [etcd-rebuild.md](etcd-rebuild.md), add rows to `topology.nix`
- Full Proxmox procedure detail: [deploy-proxmox.md](deploy-proxmox.md)
