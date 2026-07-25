# Deploy on Proxmox

Bake a qcow2, import it, attach the sops age key via cloud-init, join agents.

**New cluster?** Prefer the short path in [getting-started.md](getting-started.md).  
**This repo’s reference fleet?** See [lab.md](lab.md) for hypervisor/VMID/IP map.

## 0. Least-privilege Proxmox access (required for API import)

Do **not** use cluster root for day-to-day deploy/test. Create a scoped role once:

```bash
# on Proxmox as root
./scripts/proxmox-create-deploy-role.sh
```

Then on your workstation, source the generated env file and use API import (see [proxmox-rbac.md](proxmox-rbac.md)).

## 1. Bake images

Edit [`hosts/proxmox/topology.nix`](../hosts/proxmox/topology.nix) **before** baking (single source of truth):

- `adminSshKeys` — root SSH public keys
- `clusterVip` — preferred join/API VIP (or `""` to disable)
- `nodes` — each CP/agent: `name`, `role`, `ip`, and for servers `bootstrap` + `vipPriority`
- `bootstrapHost` — derived from the bootstrap server’s `ip` (break-glass join / tlsSan)

Joining hosts get `networking.extraHosts` mapping that IP → the bootstrap hostname when `bootstrapHost` is an IPv4.

**Before / after:** adding a CP or agent is one row in `nodes` + bake/deploy (no new host `.nix` file).

Blank starting point: [`hosts/proxmox/topology.example.nix`](../hosts/proxmox/topology.example.nix) or `./scripts/init-cluster.sh`.

```bash
nix build .#packages.x86_64-linux.proxmox-server0-qcow2 --out-link result-server-qcow
nix build .#packages.x86_64-linux.proxmox-agent0-qcow2 --out-link result-agent-qcow
```

## 2. Import VMs

```bash
# API (laptop + token env). Defaults: memory=2048, cpu=host (required for x86-64-v2 / canal).
# Pin the hypervisor with PROXMOX_NODE when spreading HA (see proxmox-rbac.md).
PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh ./result-server-qcow/nixos.qcow2 200 local-lvm rke2nixos-server0
./scripts/proxmox-import.sh ./result-agent-qcow/nixos.qcow2 201 local-lvm rke2nixos-agent0
```

Or pass a flake attr name and let the script build:

```bash
PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server0-qcow2 200
./scripts/proxmox-import.sh proxmox-agent0-qcow2 201
```

Do **not** use default `kvm64` CPU — glibc in RKE2 images needs x86-64-v2 (`cpu=host` is set by the import script).

Import default memory is **2 GiB**. Control-plane requests alone are ~1.8 GiB; at 2 GiB the node often stays **NotReady**. Prefer **≥3 GiB for control planes** and 2 GiB for agents.

## 3. Age key on first boot (cloud-init cidata ISO)

sops-nix expects `/var/lib/sops-nix/key.txt` (contents of `secrets/age.key`). **Never bake the key into the qcow2.**

Proxmox 8.x storage upload accepts `iso` (not `snippets`) for least-privilege tokens, so the helper builds a small **nocloud CIDATA** ISO and attaches it as `ide3`.

**Named hosts** (topology + `static-address.nix`): networking is Nix-owned. Attach age only:

```bash
./scripts/proxmox-age-cloudinit.sh 200 201
```

**Golden agent clones:** set `PROXMOX_HOSTNAME_<vmid>`, optional join URL, and `PROXMOX_IPCONFIG_<vmid>` — the script embeds static `network-config` in the age ISO (cloud-init binds one cidata seed). See [golden-agent.md](golden-agent.md).

Requires `genisoimage` / `mkisofs` / `xorriso` / `cloud-localds` on the workstation. Attach **before** first start (or stop + cold boot after attach).

## 4. Bring-up order

1. Start **server0**; wait for SSH, `rke2-server` active, and `/run/secrets/rke2-token` (proves age + sops).
2. Start **agent0**. With topology `joinUrl` / VIP baked in, it joins on first boot — no flake edit / re-bake between steps for a fixed topology.
3. Confirm both Ready:

```bash
# on server0
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes
/var/lib/rancher/rke2/bin/kubectl get pods -A
```

## 5. Persistence

- NixOS generations are immutable closures
- RKE2 state stays under `/var/lib/rancher/rke2` across rebuilds — do not wipe it on day-2 updates

## Success criteria

- server0 + agent0 Ready on Proxmox
- Canal + kube-proxy Running (not CrashLoop from wrong CPU type)
- Join via `https://<clusterVip|:bootstrapHost>:9345`
- Shared sops token via cloud-init age key (non-empty `/var/lib/sops-nix/key.txt`)

## Golden agent clones (optional)

See [golden-agent.md](golden-agent.md) for `proxmox-golden-agent-qcow2` (one image → N workers via cidata identity). Start with named 1+1 from [getting-started.md](getting-started.md) first.
