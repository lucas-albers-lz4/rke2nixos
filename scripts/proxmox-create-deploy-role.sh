#!/usr/bin/env bash
# One-time bootstrap (run as root on a Proxmox node): create a least-privilege
# role, pool, user, and API token for rke2nixos deploy/test — no cluster Admin.
#
# Usage:
#   ./scripts/proxmox-create-deploy-role.sh
#   POOL=rke2nixos STORAGE=local-lvm BRIDGE=vmbr0 VMID_START=200 VMID_COUNT=20 \
#     ./scripts/proxmox-create-deploy-role.sh
#
# Note: do not use env var USER — that is the login name (often "root").
# Override the PVE account with PVE_USER=name@pve if needed.
#
# Afterward, use the printed token with scripts/proxmox-import.sh (API mode).
set -euo pipefail

POOL="${POOL:-rke2nixos}"
ROLE="${ROLE:-RKE2NixosDeploy}"
GROUP="${GROUP:-rke2nixos-deploy}"
PVE_USER="${PVE_USER:-rke2nixos@pve}"
TOKEN_NAME="${TOKEN_NAME:-deploy}"
STORAGE="${STORAGE:-local-lvm}"
UPLOAD_STORAGE="${UPLOAD_STORAGE:-local}" # directory storage for qcow/ISO upload
BRIDGE="${BRIDGE:-vmbr0}"
SDN_ZONE="${SDN_ZONE:-localnetwork}"
VMID_START="${VMID_START:-200}"
VMID_COUNT="${VMID_COUNT:-20}"
PVE_PASSWORD="${PVE_PASSWORD:-}" # optional; empty = random password (prefer token)

command -v pveum >/dev/null 2>&1 || {
  echo "error: pveum not found — run on a Proxmox node as root" >&2
  exit 1
}

if [[ "$PVE_USER" != *"@"* ]]; then
  echo "error: PVE_USER must look like name@realm (got: $PVE_USER)" >&2
  exit 1
fi

# Privileges: VM lifecycle + storage space + bridge use. No Sys.Modify / Permissions.Modify / Datastore.Allocate.
PRIVS=(
  Datastore.AllocateSpace
  Datastore.AllocateTemplate
  Datastore.Audit
  Pool.Audit
  SDN.Use
  VM.Allocate
  VM.Audit
  VM.Clone
  VM.Config.CDROM
  VM.Config.CPU
  VM.Config.Cloudinit
  VM.Config.Disk
  VM.Config.HWType
  VM.Config.Memory
  VM.Config.Network
  VM.Config.Options
  VM.Console
  VM.Monitor
  VM.PowerMgmt
  VM.Snapshot
)

PRIVS_STR="${PRIVS[*]}"

echo "Creating role $ROLE…"
if pveum role config "$ROLE" &>/dev/null; then
  pveum role modify "$ROLE" --privs "$PRIVS_STR"
else
  pveum role add "$ROLE" --privs "$PRIVS_STR"
fi

echo "Creating group $GROUP…"
pveum group add "$GROUP" 2>/dev/null || true

echo "Creating user $PVE_USER…"
if pveum user config "$PVE_USER" &>/dev/null; then
  pveum user modify "$PVE_USER" --groups "$GROUP"
else
  if [[ -n "$PVE_PASSWORD" ]]; then
    pveum user add "$PVE_USER" --password "$PVE_PASSWORD" --groups "$GROUP"
  else
    # Token-only user; set a random password so the account exists.
    TMP_PASS="$(openssl rand -base64 24)"
    pveum user add "$PVE_USER" --password "$TMP_PASS" --groups "$GROUP"
    echo "note: password login enabled with a random password (prefer API token)."
  fi
fi

echo "Creating pool /$POOL…"
pvesh create /pools --poolid "$POOL" 2>/dev/null || true
# Attach storage to the pool so Datastore.AllocateSpace inherits via /pool/...
pvesh set "/pools/${POOL}" --storage "$STORAGE" 2>/dev/null || \
  pvesh set "/pools/${POOL}" -storage "$STORAGE" 2>/dev/null || \
  echo "warning: could not attach storage $STORAGE to pool (attach in UI if needed)"

# Allow API upload of disk images for import-from (needed by proxmox-import.sh).
if command -v pvesm >/dev/null 2>&1; then
  echo "Ensuring $UPLOAD_STORAGE supports content type 'import'…"
  # Keep existing content types; add import if missing.
  cur="$(pvesm config "$UPLOAD_STORAGE" 2>/dev/null | awk '/^content/ {print $2; exit}')"
  if [[ "$cur" != *import* ]]; then
    if [[ -n "$cur" ]]; then
      pvesm set "$UPLOAD_STORAGE" --content "${cur},import" || \
        echo "warning: could not add import to $UPLOAD_STORAGE — run: pvesm set $UPLOAD_STORAGE --content iso,vztmpl,backup,import"
    else
      pvesm set "$UPLOAD_STORAGE" --content iso,vztmpl,backup,snippets,import || true
    fi
  fi
fi

echo "ACLs…"
# Pool: create/manage VMs in this pool only
pveum acl modify "/pool/${POOL}" --groups "$GROUP" --role "$ROLE"
# Storage: allocate disks + upload templates/ISOs
pveum acl modify "/storage/${STORAGE}" --groups "$GROUP" --role "$ROLE"
pveum acl modify "/storage/${UPLOAD_STORAGE}" --groups "$GROUP" --role "$ROLE"
# Bridge / SDN
pveum acl modify "/sdn/zones/${SDN_ZONE}" --groups "$GROUP" --role "$ROLE"
pveum acl modify "/sdn/zones/${SDN_ZONE}/${BRIDGE}" --groups "$GROUP" --role "$ROLE" 2>/dev/null || true

# Pre-reserve VMIDs so Allocate works without Pool.Allocate privilege escalation
echo "Reserving VMID range ${VMID_START}..$((VMID_START + VMID_COUNT - 1)) on pool…"
for ((i = 0; i < VMID_COUNT; i++)); do
  vmid=$((VMID_START + i))
  pveum acl modify "/vms/${vmid}" --groups "$GROUP" --role "$ROLE" 2>/dev/null || true
done

echo "API token ${PVE_USER}!${TOKEN_NAME}…"
# Remove existing token silently if re-running (secret is only shown once at create)
pveum user token remove "$PVE_USER" "$TOKEN_NAME" 2>/dev/null || true

SECRET=""
if TOKEN_JSON="$(pveum user token add "$PVE_USER" "$TOKEN_NAME" --privsep 0 --output-format json 2>/dev/null)"; then
  echo "$TOKEN_JSON"
  if command -v jq >/dev/null 2>&1; then
    SECRET="$(echo "$TOKEN_JSON" | jq -r '.value // empty')"
  else
    SECRET="$(echo "$TOKEN_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
else
  TOKEN_OUT="$(pveum user token add "$PVE_USER" "$TOKEN_NAME" --privsep 0)"
  echo "$TOKEN_OUT"
  # Table output (unicode box drawing) — grab the value row
  SECRET="$(echo "$TOKEN_OUT" | awk '
    /value/ {
      # split on │ or |
      n = split($0, a, /│|\|/)
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
      }
      # usually: empty, "value", secret, empty
      if (n >= 3 && a[2] == "value") { print a[3]; exit }
      if (n >= 2 && a[1] == "value") { print a[2]; exit }
    }
  ')"
fi

if [[ -z "$SECRET" || "$SECRET" == "null" ]]; then
  echo "error: could not parse API token secret from pveum output." >&2
  echo "Create manually, then put the value in PROXMOX_TOKEN_SECRET:" >&2
  echo "  pveum user token remove '$PVE_USER' '$TOKEN_NAME'" >&2
  echo "  pveum user token add '$PVE_USER' '$TOKEN_NAME' --privsep 0 --output-format json" >&2
  exit 1
fi

CREDS_FILE="${CREDS_FILE:-$HOME/rke2nixos-proxmox.env}"
# Prefer an explicit reachable address (IP) for API clients that lack LAN DNS.
API_HOST="${API_HOST:-}"
if [[ -z "$API_HOST" ]]; then
  API_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
if [[ -z "$API_HOST" ]]; then
  API_HOST="$(hostname -f 2>/dev/null || hostname)"
fi
API_NODE="$(hostname -s 2>/dev/null || hostname)"

umask 077
cat >"$CREDS_FILE" <<EOF
# Generated by proxmox-create-deploy-role.sh — keep private.
# Source before deploy:  set +H; set -a; source $CREDS_FILE; set +a
# Or: PROXMOX_ENV=$CREDS_FILE ./scripts/proxmox-import.sh …
# Override at generate time: API_HOST=192.168.1.12 ./scripts/proxmox-create-deploy-role.sh
PROXMOX_HOST='${API_HOST}'
PROXMOX_NODE='${API_NODE}'
PROXMOX_PORT=8006
PROXMOX_TOKEN_ID='${PVE_USER}!${TOKEN_NAME}'
PROXMOX_TOKEN_SECRET='${SECRET}'
PROXMOX_POOL='${POOL}'
PROXMOX_STORAGE='${STORAGE}'
PROXMOX_UPLOAD_STORAGE='${UPLOAD_STORAGE}'
PROXMOX_BRIDGE='${BRIDGE}'
PROXMOX_VMID_START=${VMID_START}
PROXMOX_INSECURE=1
EOF

echo
echo "Wrote $CREDS_FILE"
echo
echo "What this user CAN do:"
echo "  - Create/start/stop/configure VMs in pool '$POOL' (VMIDs ~${VMID_START}+)"
echo "  - Allocate disks on $STORAGE; upload images to $UPLOAD_STORAGE"
echo "  - Attach NIC to $BRIDGE"
echo
echo "What this user CANNOT do:"
echo "  - Cluster Admin / Sys.Modify / node install / user & ACL changes"
echo "  - Create or delete storages, SDN zones, or other pools"
echo
echo "Next:"
echo "  1. Copy $CREDS_FILE to your workstation (not into git)."
echo "  2. source it and run: ./scripts/proxmox-import.sh …"
echo "  3. See docs/proxmox-rbac.md"
