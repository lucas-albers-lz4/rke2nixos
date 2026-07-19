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

## Still needs a human once

- First run of `proxmox-create-deploy-role.sh` as **root**
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
