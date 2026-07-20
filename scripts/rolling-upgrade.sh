#!/usr/bin/env bash
# Rolling upgrade: cordon → drain → deploy-host.sh → wait Ready → uncordon.
# Inventory: hosts/proxmox/inventory.nix (derived from topology.nix — edit topology).
#
# Usage:
#   ./scripts/rolling-upgrade.sh                  # all CPs then agents
#   ./scripts/rolling-upgrade.sh --dry-run
#   ./scripts/rolling-upgrade.sh --only agents
#   READY_TIMEOUT=900 ./scripts/rolling-upgrade.sh
#
# Stuck CP: stop the roll; on that node run `nixos-rebuild switch --rollback`
# (or deploy previous generation). Generation rollback does not rewind etcd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="${INVENTORY:-$ROOT/hosts/proxmox/inventory.nix}"
DEPLOY="$ROOT/scripts/deploy-host.sh"
READY_TIMEOUT="${READY_TIMEOUT:-600}"
KUBECONFIG_REMOTE="${KUBECONFIG_REMOTE:-/etc/rancher/rke2/rke2.yaml}"
KUBECTL_REMOTE="${KUBECTL_REMOTE:-/var/lib/rancher/rke2/bin/kubectl}"

DRY_RUN=0
ONLY="all"

usage() {
  echo "usage: $0 [--dry-run] [--only all|cps|agents]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --only)
      ONLY="${2:-}"
      shift 2
      [[ "$ONLY" == all || "$ONLY" == cps || "$ONLY" == agents ]] || usage
      ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [[ ! -f "$INVENTORY" ]]; then
  echo "error: inventory not found: $INVENTORY" >&2
  exit 1
fi

# Emit lines: role|config|target|nodeName|bootstrap
mapfile -t NODES < <(nix-instantiate --eval --strict --json -E "
  let
    inv = import $INVENTORY;
    lib = (import <nixpkgs> {}).lib;
    cps = map (n: \"cp|\${n.config}|\${n.target}|\${n.nodeName}|\${if n.bootstrap then \"1\" else \"0\"}\") inv.controlPlanes;
    agents = map (n: \"agent|\${n.config}|\${n.target}|\${n.nodeName}|0\") inv.agents;
  in cps ++ agents
" 2>/dev/null | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))')

# Prefer flake-evaluated nixpkgs if nix-instantiate path fails (no NIX_PATH).
if [[ ${#NODES[@]} -eq 0 ]]; then
  mapfile -t NODES < <(
    if command -v nix >/dev/null 2>&1; then
      nix eval --impure --json --expr "
        let inv = import $INVENTORY;
        in (map (n: \"cp|\${n.config}|\${n.target}|\${n.nodeName}|\${if n.bootstrap then \"1\" else \"0\"}\") inv.controlPlanes)
        ++ (map (n: \"agent|\${n.config}|\${n.target}|\${n.nodeName}|0\") inv.agents)
      " | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))'
    else
      echo "error: need nix to evaluate inventory" >&2
      exit 1
    fi
  )
fi

# Rolling order: non-bootstrap CPs first, then bootstrap CP, then agents.
ordered=()
for line in "${NODES[@]}"; do
  IFS='|' read -r role config target node bootstrap <<<"$line"
  [[ "$role" == cp && "$bootstrap" == 0 ]] || continue
  [[ "$ONLY" == all || "$ONLY" == cps ]] || continue
  ordered+=("$line")
done
for line in "${NODES[@]}"; do
  IFS='|' read -r role config target node bootstrap <<<"$line"
  [[ "$role" == cp && "$bootstrap" == 1 ]] || continue
  [[ "$ONLY" == all || "$ONLY" == cps ]] || continue
  ordered+=("$line")
done
for line in "${NODES[@]}"; do
  IFS='|' read -r role config target node bootstrap <<<"$line"
  [[ "$role" == agent ]] || continue
  [[ "$ONLY" == all || "$ONLY" == agents ]] || continue
  ordered+=("$line")
done

if [[ ${#ordered[@]} -eq 0 ]]; then
  echo "error: no nodes selected (only=$ONLY)" >&2
  exit 1
fi

# kubectl via first reachable CP (bootstrap preferred)
kubectl_cp() {
  local bootstrap_target=""
  local any_target=""
  for line in "${NODES[@]}"; do
    IFS='|' read -r role config target node bootstrap <<<"$line"
    [[ "$role" == cp ]] || continue
    any_target="$target"
    if [[ "$bootstrap" == 1 ]]; then
      bootstrap_target="$target"
      break
    fi
  done
  local api="${bootstrap_target:-$any_target}"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$api" \
    "export KUBECONFIG=$KUBECONFIG_REMOTE; $KUBECTL_REMOTE $*"
}

wait_ready() {
  local name="$1"
  local deadline=$((SECONDS + READY_TIMEOUT))
  echo "Waiting for node/$name Ready (timeout ${READY_TIMEOUT}s)…"
  while (( SECONDS < deadline )); do
    local ready
    ready="$(kubectl_cp get node "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    if [[ "$ready" == "True" ]]; then
      echo "node/$name is Ready"
      return 0
    fi
    sleep 10
  done
  echo "error: node/$name not Ready within ${READY_TIMEOUT}s — stop the roll; consider nixos-rebuild switch --rollback on $name" >&2
  return 1
}

echo "Rolling upgrade order (${#ordered[@]} node(s)):"
printf '  %s\n' "${ordered[@]}"
echo "Inventory: $INVENTORY"
echo "Note: generation rollback does not rewind etcd / containerd / CNI state under /var/lib/rancher/rke2."

for line in "${ordered[@]}"; do
  IFS='|' read -r role config target node bootstrap <<<"$line"
  echo
  echo "=== $role $node ($config → $target) ==="

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "dry-run: would cordon/drain/deploy/uncordon $node"
    continue
  fi

  # Skip nodes that are not yet in the cluster (inventory placeholders for future CPs).
  if ! kubectl_cp get node "$node" >/dev/null 2>&1; then
    echo "warning: node/$node not in cluster — deploy only (no cordon/drain)"
    "$DEPLOY" "$config" "$target"
    continue
  fi

  kubectl_cp cordon "$node"
  kubectl_cp drain "$node" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --timeout="${READY_TIMEOUT}s" || {
      echo "warning: drain returned non-zero; continuing with deploy" >&2
    }

  "$DEPLOY" "$config" "$target"
  wait_ready "$node"
  kubectl_cp uncordon "$node"
done

echo
echo "Rolling upgrade finished."
