#!/usr/bin/env bash
# Import a baked qcow2 into Proxmox.
#
# Local (on node, with qm):
#   ./scripts/proxmox-import.sh /path/to/nixos.qcow2 200 local-lvm server0
#
# API (laptop + least-privilege token):
#   PROXMOX_ENV=../tmp-rke2nixos/rke2nixos-proxmox.env \
#     ./scripts/proxmox-import.sh proxmox-server0-qcow2 200
#
# Requires: local storage supports content type "import" (enabled by
# proxmox-create-deploy-role.sh). Disk lands on PROXMOX_STORAGE (local-lvm).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_proxmox_env() {
  if [[ -n "${PROXMOX_HOST:-}" && -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" ]]; then
    return 0
  fi

  local candidates=()
  if [[ -n "${PROXMOX_ENV:-}" ]]; then
    candidates+=("${PROXMOX_ENV}")
  fi
  candidates+=(
    "$ROOT/rke2nixos-proxmox.env"
    "$ROOT/../tmp-rke2nixos/rke2nixos-proxmox.env"
    "$HOME/rke2nixos-proxmox.env"
    "$HOME/.config/rke2nixos/proxmox.env"
  )

  local f
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "Loading Proxmox env from $f"
      set -a
      set +H
      # shellcheck source=/dev/null
      source "$f"
      set +a
      return 0
    fi
  done
  return 1
}

usage() {
  cat <<'EOF' >&2
usage: ./scripts/proxmox-import.sh <qcow2-path|flake-attr> <vmid> [storage] [vmname]

  PROXMOX_ENV=../tmp-rke2nixos/rke2nixos-proxmox.env \
    ./scripts/proxmox-import.sh proxmox-server0-qcow2 200
EOF
  exit 1
}

load_proxmox_env || true
[[ $# -ge 2 ]] || usage

SRC="$1"
VMID="$2"
STORAGE="${3:-${PROXMOX_STORAGE:-local-lvm}}"
VMNAME="${4:-rke2nixos-$VMID}"
POOL="${PROXMOX_POOL:-rke2nixos}"
BRIDGE="${PROXMOX_BRIDGE:-vmbr0}"
UPLOAD_STORAGE="${PROXMOX_UPLOAD_STORAGE:-local}"
NODE="${PROXMOX_NODE:-}"
PORT="${PROXMOX_PORT:-8006}"
HOST="${PROXMOX_HOST:-}"
# Default 2048 so two lab VMs fit a small hypervisor; control-plane often needs
# PROXMOX_MEMORY=3072 (or higher) — see docs/deploy-proxmox.md.
MEMORY="${PROXMOX_MEMORY:-2048}"

missing=()
[[ -n "${PROXMOX_HOST:-}" ]] || missing+=("PROXMOX_HOST")
[[ -n "${PROXMOX_TOKEN_ID:-}" ]] || missing+=("PROXMOX_TOKEN_ID")
[[ -n "${PROXMOX_TOKEN_SECRET:-}" && "${PROXMOX_TOKEN_SECRET}" != REPLACE* ]] || missing+=("PROXMOX_TOKEN_SECRET")

if ((${#missing[@]} > 0)); then
  if command -v qm >/dev/null 2>&1; then
    echo "note: incomplete API env (${missing[*]}); using local qm mode" >&2
  else
    echo "error: missing Proxmox API vars: ${missing[*]}" >&2
    echo "  PROXMOX_ENV=../tmp-rke2nixos/rke2nixos-proxmox.env $0 $*" >&2
    exit 1
  fi
fi

export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes
warn-dirty = false}"

resolve_src() {
  if [[ -f "$SRC" ]]; then
    return
  fi
  local out_link="$ROOT/result-qcow-${SRC}"
  echo "Building flake package .#$SRC (x86_64-linux)…"
  nix --extra-experimental-features 'nix-command flakes' \
    build "$ROOT#packages.x86_64-linux.$SRC" --out-link "$out_link"
  SRC="$(find -L "$out_link" -type f \( -name '*.qcow2' -o -name 'nixos*.qcow2' \) | head -n1)"
  if [[ -z "$SRC" ]]; then
    SRC="$(find -L "$out_link" -type f | head -n1)"
  fi
  echo "Using image: $SRC"
}

api_mode() {
  [[ -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" && -n "$HOST" ]]
}

# POST/PUT/GET JSON; return 1 on HTTP/Proxmox errors (do not exit — callers decide).
curl_pve() {
  local method="$1" path="$2"
  shift 2
  local url="https://${HOST}:${PORT}${path}"
  local opts=(-sS -X "$method" -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}")
  if [[ "${PROXMOX_INSECURE:-0}" == "1" ]]; then
    opts+=(-k)
  fi
  local body http
  body="$(curl "${opts[@]}" -w '\n%{http_code}' "$url" "$@" || true)"
  http="$(echo "$body" | tail -n1)"
  body="$(echo "$body" | sed '$d')"
  if [[ "$http" != 2* ]]; then
    echo "error: HTTP $http for $method $path" >&2
    echo "$body" | jq -r '.message // .' 2>/dev/null || echo "$body" >&2
    return 1
  fi
  if echo "$body" | jq -e 'has("errors") and (.errors != null)' >/dev/null 2>&1; then
    echo "error: Proxmox rejected $method $path" >&2
    echo "$body" | jq . >&2
    return 1
  fi
  if echo "$body" | jq -e '.message != null and .data == null' >/dev/null 2>&1; then
    echo "error: $(echo "$body" | jq -r .message)" >&2
    return 1
  fi
  echo "$body"
}

wait_task() {
  local upid="$1"
  [[ -n "$upid" && "$upid" != null ]] || return 0
  # UPID:node:...
  local task_node
  task_node="$(echo "$upid" | cut -d: -f2)"
  echo "Waiting for task on ${task_node}: ${upid}"
  local i status
  for i in $(seq 1 3600); do
    status="$(curl_pve GET "/api2/json/nodes/${task_node}/tasks/${upid}/status")"
    local st exitstatus
    st="$(echo "$status" | jq -r '.data.status')"
    exitstatus="$(echo "$status" | jq -r '.data.exitstatus // empty')"
    if [[ "$st" == "stopped" ]]; then
      if [[ "$exitstatus" == "OK" ]]; then
        return 0
      fi
      echo "error: task failed: $exitstatus" >&2
      curl_pve GET "/api2/json/nodes/${task_node}/tasks/${upid}/log?limit=50" | jq -r '.data[].t' >&2 || true
      exit 1
    fi
    sleep 2
  done
  echo "error: task timed out: $upid" >&2
  exit 1
}

pick_node() {
  if [[ -n "$NODE" ]]; then
    local status_json active
    if status_json="$(curl_pve GET "/api2/json/nodes/${NODE}/storage/${STORAGE}/status")"; then
      active="$(echo "$status_json" | jq -r '.data.active // 0')"
      if [[ "$active" == "1" || "$active" == "true" ]]; then
        echo "Using node: $NODE (storage $STORAGE active)"
        return 0
      fi
    fi
    echo "warning: storage ${STORAGE} not active on ${NODE}; auto-picking a node…" >&2
  fi
  NODE="$(curl_pve GET /api2/json/cluster/resources | jq -r --arg s "$STORAGE" '
    .data[]
    | select(.type=="storage" and .storage==$s and .status=="available")
    | .node
  ' | head -1)" || true
  if [[ -z "$NODE" || "$NODE" == "null" ]]; then
    local n
    for n in $(curl_pve GET /api2/json/nodes | jq -r '.data[].node'); do
      if curl_pve GET "/api2/json/nodes/${n}/storage/${STORAGE}/status" 2>/dev/null | jq -e '.data.active == 1' >/dev/null 2>&1; then
        NODE="$n"
        break
      fi
    done
  fi
  if [[ -z "$NODE" || "$NODE" == "null" ]]; then
    echo "error: no node has active storage '$STORAGE'" >&2
    exit 1
  fi
  echo "Using node: $NODE (storage $STORAGE)"
}

# Missing VMs return HTTP 500 on PVE — never use curl_pve here (it would abort).
vm_exists() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' \
    -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
    "https://${HOST}:${PORT}/api2/json/nodes/${NODE}/qemu/${VMID}/status/current")"
  [[ "$code" == "200" ]]
}

import_local() {
  command -v qm >/dev/null 2>&1 || {
    echo "error: qm not found and API env not set" >&2
    exit 1
  }

  # cpu=host: nixpkgs/glibc and RKE2 images need x86-64-v2 (default kvm64 breaks iptables/canal)
  local create_args=(
    "$VMID"
    --name "$VMNAME"
    --memory "$MEMORY"
    --cores 2
    --cpu host
    --net0 "virtio,bridge=${BRIDGE}"
    --ostype l26
    --scsihw virtio-scsi-pci
    --agent enabled=1
    --bios ovmf
    --machine q35
    --vga std
  )
  if [[ -n "$POOL" ]]; then
    create_args+=(--pool "$POOL")
  fi

  qm create "${create_args[@]}"
  qm importdisk "$VMID" "$SRC" "$STORAGE"
  qm set "$VMID" --scsi0 "${STORAGE}:vm-${VMID}-disk-0"
  qm set "$VMID" --boot order=scsi0
  qm set "$VMID" --serial0 socket --vga serial0
}

import_api() {
  command -v curl >/dev/null 2>&1 || {
    echo "error: curl required for API mode" >&2
    exit 1
  }
  command -v jq >/dev/null 2>&1 || {
    echo "error: jq required for API mode" >&2
    exit 1
  }

  pick_node

  # Create VM if missing
  if vm_exists; then
    echo "VM $VMID already exists on $NODE — reusing"
  else
    echo "Creating VM $VMID ($VMNAME) in pool $POOL on $NODE…"
    local create_json
    create_json="$(curl_pve POST "/api2/json/nodes/${NODE}/qemu" \
      --data-urlencode "vmid=${VMID}" \
      --data-urlencode "name=${VMNAME}" \
      --data-urlencode "memory=${MEMORY}" \
      --data-urlencode "cores=2" \
      --data-urlencode "cpu=host" \
      --data-urlencode "net0=model=virtio,bridge=${BRIDGE}" \
      --data-urlencode "ostype=l26" \
      --data-urlencode "scsihw=virtio-scsi-pci" \
      --data-urlencode "agent=1" \
      --data-urlencode "bios=ovmf" \
      --data-urlencode "machine=q35" \
      --data-urlencode "pool=${POOL}" \
      --data-urlencode "vga=std")" || exit 1
    wait_task "$(echo "$create_json" | jq -r '.data')"
    # EFI vars disk required for OVMF (NixOS images are EFI-only)
    curl_pve PUT "/api2/json/nodes/${NODE}/qemu/${VMID}/config" \
      --data-urlencode "efidisk0=${STORAGE}:1,efitype=4m,pre-enrolled-keys=0" >/dev/null \
      || echo "warning: could not add efidisk0 — set manually: qm set $VMID --bios ovmf --efidisk0 ${STORAGE}:1,efitype=4m,pre-enrolled-keys=0" >&2
  fi

  local remote_name="rke2nixos-${VMID}.qcow2"
  echo "Uploading $(basename "$SRC") → ${UPLOAD_STORAGE} (content=import) on ${NODE}…"
  echo "(large images take a while)"
  local up_json
  # Do not use curl -f on multipart the same way — use explicit check
  up_json="$(
    local opts=(-sS -X POST -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}")
    [[ "${PROXMOX_INSECURE:-0}" == "1" ]] && opts+=(-k)
    curl "${opts[@]}" "https://${HOST}:${PORT}/api2/json/nodes/${NODE}/storage/${UPLOAD_STORAGE}/upload" \
      -F "content=import" \
      -F "filename=@${SRC};filename=${remote_name}"
  )"
  if echo "$up_json" | jq -e '.message != null and .data == null' >/dev/null 2>&1; then
    echo "error: upload failed: $(echo "$up_json" | jq -r .message)" >&2
    echo "hint: on Proxmox as root enable import content:" >&2
    echo "  pvesm set ${UPLOAD_STORAGE} --content iso,vztmpl,backup,snippets,import" >&2
    echo "Or re-run ./scripts/proxmox-create-deploy-role.sh after pulling the latest script." >&2
    exit 1
  fi
  wait_task "$(echo "$up_json" | jq -r '.data')"

  local listed volid
  listed="$(curl_pve GET "/api2/json/nodes/${NODE}/storage/${UPLOAD_STORAGE}/content")"
  volid="$(echo "$listed" | jq -r --arg n "$remote_name" '.data[]? | select(.volid|endswith($n)) | .volid' | head -1)"
  if [[ -z "$volid" || "$volid" == "null" ]]; then
    volid="${UPLOAD_STORAGE}:import/${remote_name}"
    echo "warning: volume not listed yet; trying ${volid}"
  fi

  echo "Importing ${volid} → ${STORAGE} as scsi0…"
  local cfg_json
  cfg_json="$(curl_pve PUT "/api2/json/nodes/${NODE}/qemu/${VMID}/config" \
    --data-urlencode "scsi0=${STORAGE}:0,import-from=${volid}" \
    --data-urlencode "boot=order=scsi0")"
  # config PUT may return null data on success or a task
  wait_task "$(echo "$cfg_json" | jq -r '.data // empty')"

  echo "OK: VM $VMID on $NODE"
}

resolve_src

if api_mode; then
  echo "API mode → ${HOST} as ${PROXMOX_TOKEN_ID}"
  import_api
else
  echo "Local qm mode"
  import_local
fi

echo
echo "Created/updated VM $VMID ($VMNAME) pool=${POOL} node=${NODE:-local}."
echo "Defaults: memory=${MEMORY} cpu=host (x86-64-v2)."
echo "Before first start:"
echo "  1. Attach age key cloud-init: ./scripts/proxmox-age-cloudinit.sh $VMID"
echo "  2. Confirm SSH keys + bootstrapHost in hosts/proxmox/settings.nix"
echo "  3. Start VM $VMID (UI name '$VMNAME', guest hostname may differ)"
echo "Join URL for agents: https://<bootstrapHost>:9345"
