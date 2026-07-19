# Deploy on Proxmox (R5)

Bake a qcow2, import it, attach the sops age key via cloud-init, join agents.

## 0. Least-privilege Proxmox access (recommended)

Do **not** use cluster root for day-to-day deploy/test. Create a scoped role once:

```bash
# on Proxmox as root
./scripts/proxmox-create-deploy-role.sh
```

Then on your workstation, source the generated env file and use API import (see [proxmox-rbac.md](proxmox-rbac.md)).

## 1. Bake images

Edit [`hosts/proxmox/settings.nix`](../hosts/proxmox/settings.nix) **before** baking:

- `adminSshKeys` — root SSH public keys
- `bootstrapHost` — sticky join target (prefer server0's reserved IP, e.g. `192.168.1.24`)

When `bootstrapHost` is an IPv4, joining hosts (`agent0`, `server1`, `server2`) get `networking.extraHosts` mapping that IP → `server0`.

```bash
nix build .#packages.x86_64-linux.proxmox-server0-qcow2 --out-link result-server-qcow
nix build .#packages.x86_64-linux.proxmox-agent0-qcow2 --out-link result-agent-qcow
```

## 2. Import VMs

```bash
# API (laptop + token env). Defaults: memory=2048, cpu=host (required for x86-64-v2 / canal).
# Pin the hypervisor with PROXMOX_NODE when spreading HA (see proxmox-rbac.md).
./scripts/proxmox-import.sh ./result-server-qcow/nixos.qcow2 200 local-lvm rke2nixos-200
./scripts/proxmox-import.sh ./result-agent-qcow/nixos.qcow2 201 local-lvm rke2nixos-201
```

Or pass a flake attr name and let the script build:

```bash
PROXMOX_NODE=L11 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server0-qcow2 200
PROXMOX_NODE=L11 ./scripts/proxmox-import.sh proxmox-agent0-qcow2 201

# HA control-planes (R6): L7 / L8 — verify free RAM first (other guests may already use ~8–9 GiB)
PROXMOX_NODE=L7 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server1-qcow2 202
PROXMOX_NODE=L8 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server2-qcow2 203
```

Lab hypervisors: **L11**, **L7**, **L8**, **L9** (`rke2ops@192.168.1.{11,7,8,9}`). **L12** is unused for this lab (insufficient memory).

Do **not** use default `kvm64` CPU — glibc in RKE2 images needs x86-64-v2 (`cpu=host` is set by the import script).

Lab memory default is **2 GiB** per VM so two guests fit a small hypervisor. Control-plane requests alone are ~1.8 GiB; at 2 GiB the node often stays **NotReady** (controller-manager / canal cannot schedule). Prefer **≥3 GiB for server0** and 2 GiB for agents (total under 8 GiB), or free other host VMs first.

## 3. Age key on first boot (cloud-init cidata ISO)

sops-nix expects `/var/lib/sops-nix/key.txt` (contents of `secrets/age.key`). **Never bake the key into the qcow2.**

Proxmox 8.x storage upload accepts `iso` (not `snippets`) for least-privilege tokens, so the helper builds a small **nocloud CIDATA** ISO (age `write_files` only) and attaches it as `ide3`. Sticky IPs use Proxmox's own cloud-init drive (`ide2` + `ipconfig0`):

```bash
# Sticky IPs: prefer DHCP reservations matching settings.bootstrapHost.
# Proxmox ipconfig0 is set when these are exported (ide2 cloudinit drive):
export PROXMOX_IPCONFIG_200='ip=192.168.1.24/24,gw=192.168.1.1'
export PROXMOX_IPCONFIG_201='ip=192.168.1.25/24,gw=192.168.1.1'
# Control-plane: override import default if needed
# PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh …

./scripts/proxmox-age-cloudinit.sh 200 201
```

Requires `genisoimage` / `mkisofs` / `xorriso` / `cloud-localds` on the workstation. Attach **before** first start (or stop + cold boot after attach). Do not put `network-config` in the age ISO — that fights NixOS networkd.

## 4. Bring-up order

1. Start **server0** (VM 200); wait for SSH, `rke2-server` active, and `/run/secrets/rke2-token` (proves age + sops).
2. Start **agent0** (VM 201). With sticky `bootstrapHost` baked in, it joins on first boot — no flake edit / re-bake between steps.
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

## Success criteria (R5)

- server0 + agent0 Ready on Proxmox
- Canal + kube-proxy Running (not CrashLoop from wrong CPU type)
- Join via sticky `https://<bootstrapHost>:9345` without live `/etc/hosts` hacks
- Shared sops token via cloud-init age key (non-empty `/var/lib/sops-nix/key.txt`)
