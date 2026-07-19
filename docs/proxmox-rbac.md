# Proxmox least-privilege deploy role

Goal: deploy and test rke2nixos VMs **without** cluster `Administrator` / root on every action.

## One-time setup (cluster admin)

SSH to a Proxmox node as root and run from this repo (or copy the script over):

```bash
# optional overrides
export POOL=rke2nixos
export STORAGE=local-lvm
export UPLOAD_STORAGE=local    # must be a "Directory" storage (for qcow upload)
export BRIDGE=vmbr0
export VMID_START=200
export VMID_COUNT=20

./scripts/proxmox-create-deploy-role.sh
```

Creates:

| Object | Name (defaults) | Purpose |
|--------|-----------------|---------|
| Role | `RKE2NixosDeploy` | VM + datastore space + SDN.Use only |
| Group | `rke2nixos-deploy` | Holds the role |
| User | `rke2nixos@pve` | Token owner (`PVE_USER`, not shell `$USER`) |
| Token | `rke2nixos@pve!deploy` | API auth for laptop/CI/agent |
| Pool | `rke2nixos` | Scope for VMs |
| ACLs | `/pool/…`, `/storage/…`, `/sdn/zones/…`, `/vms/200–219` | Least privilege paths |

Also ensure `PROXMOX_TOKEN_SECRET` in that file is a real UUID-like secret — not `REPLACE_WITH_SECRET…`. If it is a placeholder, recreate the token on the node:

```bash
pveum user token remove rke2nixos@pve deploy
pveum user token add rke2nixos@pve deploy --privsep 0 --output-format json
# put .value into PROXMOX_TOKEN_SECRET in the env file
```

### Privileges included

`VM.Allocate/Audit/Clone/Console/Monitor/PowerMgmt/Snapshot`, `VM.Config.*` (disk/net/cpu/memory/cloudinit/…), `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit`, `Pool.Audit`, `SDN.Use`.

### Privileges excluded

`Administrator`, `Sys.Modify`, `Permissions.Modify`, `Datastore.Allocate` (create/delete storages), `Pool.Allocate`, user/realm management, node package installs.

## Day-to-day (deploy user / agent)

```bash
set -a
source ~/rke2nixos-proxmox.env   # or wherever you stored the creds
set +a

# Bake locally, then import via API (no Proxmox root shell required)
./scripts/proxmox-import.sh proxmox-server0-qcow2 200
./scripts/proxmox-import.sh proxmox-agent0-qcow2 201
```

Use VMIDs in the reserved range (`PROXMOX_VMID_START` …). Always pass/`PROXMOX_POOL` so allocate checks hit the pool ACL.

## Node SSH ops user (`qm guest`)

API tokens cannot run local `qm`. For guest IP discovery, create a **Linux** user on each Proxmox node (accounts are per-node, not cluster-wide).

Lab nodes (usable for rke2nixos guests):

| Node | SSH | Notes |
|------|-----|-------|
| L11 | `rke2ops@192.168.1.11` | server0 (200, static `.32`), agent0 (201) |
| L7 | `rke2ops@192.168.1.7` | server1 (202, static `.36`) |
| L8 | `rke2ops@192.168.1.8` | server2 (203, static `.35`) |
| L9 | `rke2ops@192.168.1.9` | spare capacity |
| L12 | `rke2ops@192.168.1.12` | **Unused for lab** (insufficient memory) |

One-time as **root** on each node:

```bash
OPS_USER=rke2ops
OPS_PUBKEY='PASTE_YOUR_WORKSTATION_ED25519_PUBKEY_HERE'

adduser --disabled-password --gecos 'rke2nixos qm ops' "$OPS_USER"
install -d -m 700 -o "$OPS_USER" -g "$OPS_USER" "/home/${OPS_USER}/.ssh"
printf '%s\n' "$OPS_PUBKEY" > "/home/${OPS_USER}/.ssh/authorized_keys"
chown "$OPS_USER:$OPS_USER" "/home/${OPS_USER}/.ssh/authorized_keys"
chmod 600 "/home/${OPS_USER}/.ssh/authorized_keys"

cat > /etc/sudoers.d/rke2ops-qm <<EOF
${OPS_USER} ALL=(root) NOPASSWD: /usr/sbin/qm guest *, /usr/sbin/qm status *, /usr/sbin/qm list, /usr/sbin/qm config *
EOF
chmod 440 /etc/sudoers.d/rke2ops-qm
visudo -cf /etc/sudoers.d/rke2ops-qm
```

Discover guest IPs (**on the node that owns the VM**):

```bash
ssh rke2ops@192.168.1.11 'sudo qm list'
ssh rke2ops@192.168.1.11 'sudo qm guest cmd 200 network-get-interfaces'
ssh rke2ops@192.168.1.11 'sudo qm guest cmd 201 network-get-interfaces'
ssh rke2ops@192.168.1.7  'sudo qm guest cmd 202 network-get-interfaces'  # after import
ssh rke2ops@192.168.1.8  'sudo qm guest cmd 203 network-get-interfaces'
```

Parse `ens18` IPv4 addresses; skip `lo`, `10.42.*`, and cali/flannel. Prefer sticky lab IPs (`.24` / `.25`) when present alongside DHCP.

### Targeting a specific Proxmox node on import

[`scripts/proxmox-import.sh`](../scripts/proxmox-import.sh) honors `PROXMOX_NODE` (Proxmox node name, e.g. `L7` / `L8` / `L11`). If unset, it auto-picks a node with active `PROXMOX_STORAGE`.

```bash
# Example: place server1 on L7, server2 on L8 (CP memory ≥3072)
PROXMOX_NODE=L7 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server1-qcow2 202
PROXMOX_NODE=L8 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server2-qcow2 203
```

Use VMIDs in the reserved pool range (200–219). Do not reuse VMIDs already present on a node (e.g. 100–110 on L7/L8/L9).

## Still needs a human once

- First run of `proxmox-create-deploy-role.sh` as **root**
- Creating the `rke2ops` Linux user + sudoers on each node (above)
- Injecting `secrets/age.key` into guests (cloud-init / mount) — guest root, not Proxmox root
- If `UPLOAD_STORAGE=local` is full or not a Directory type, point it at another dir storage the role can write

## Verify the role is limited

As the token user you should be able to create a VM in pool `rke2nixos` and fail to:

```bash
# examples of denied actions
pvesh get /nodes                     # may work read-only depending on ACLs
pveum user list                      # should fail
pvesh create /storage …              # should fail
```

## Related

- [deploy-proxmox.md](deploy-proxmox.md) — bake, age key, join order
- [`hosts/proxmox/settings.nix`](../hosts/proxmox/settings.nix) — SSH keys + join URL
