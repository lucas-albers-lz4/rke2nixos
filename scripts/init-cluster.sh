#!/usr/bin/env bash
# Scaffold secrets + optional topology for a new Proxmox cluster.
#
# Default: never overwrite hosts/proxmox/topology.nix (safe on the live lab clone).
#   ./scripts/init-cluster.sh
#
# Fork / personal cluster from the example:
#   ./scripts/init-cluster.sh --from-example \
#     --ssh-key 'ssh-ed25519 AAAA… you@laptop' \
#     --gateway 192.168.10.1 \
#     --vip 192.168.10.29 \
#     --bootstrap-ip 192.168.10.10 \
#     --agent-ip 192.168.10.20
#
# Env: same as other scripts; uses ./scripts/sops-bootstrap.sh for age + token.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TOPOLOGY="$ROOT/hosts/proxmox/topology.nix"
EXAMPLE="$ROOT/hosts/proxmox/topology.example.nix"

FROM_EXAMPLE=0
SSH_KEY=""
GATEWAY=""
VIP=""
BOOTSTRAP_IP=""
AGENT_IP=""
SKIP_SOPS=0

usage() {
  cat <<'EOF'
usage: ./scripts/init-cluster.sh [options]

  --from-example     Backup topology.nix (if present) and replace from topology.example.nix
  --ssh-key KEY      Set adminSshKeys (only when writing from example)
  --gateway IP       Set gateway
  --vip IP           Set clusterVip (use empty string via --vip '' to clear — pass as --vip=)
  --bootstrap-ip IP  Set server0 ip
  --agent-ip IP      Set agent0 ip
  --skip-sops        Do not run sops-bootstrap.sh
  -h, --help         Show this help

Without --from-example:
  - Runs sops-bootstrap (unless --skip-sops)
  - If topology.nix is missing, copies the example
  - If topology.nix exists, leaves it untouched (lab-safe)

Next steps are printed at the end; see docs/getting-started.md.
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-example) FROM_EXAMPLE=1; shift ;;
    --ssh-key) SSH_KEY="${2:-}"; shift 2 ;;
    --gateway) GATEWAY="${2:-}"; shift 2 ;;
    --vip) VIP="${2:-}"; shift 2 ;;
    --bootstrap-ip) BOOTSTRAP_IP="${2:-}"; shift 2 ;;
    --agent-ip) AGENT_IP="${2:-}"; shift 2 ;;
    --skip-sops) SKIP_SOPS=1; shift ;;
    -h|--help) usage 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage 2
      ;;
  esac
done

hint_nix() {
  if command -v nix >/dev/null 2>&1; then
    echo "Nix: found ($(nix --version 2>/dev/null | head -1))"
  else
    echo "Nix: not on PATH — prefer ./scripts/nix-docker.sh for builds (see docs/getting-started.md)"
  fi
}

patch_topology() {
  local file="$1"
  # Placeholders from topology.example.nix
  if [[ -n "$SSH_KEY" ]]; then
    # Escape for sed replacement
    local esc
    esc="$(printf '%s' "$SSH_KEY" | sed -e 's/[\/&]/g')"
    sed -i "s|REPLACE_SSH_KEY|$esc|" "$file"
  fi
  if [[ -n "$GATEWAY" ]]; then
    sed -i "s|gateway = \"192.0.2.1\"|gateway = \"$GATEWAY\"|" "$file"
  fi
  if [[ -n "$VIP" ]]; then
    sed -i "s|clusterVip = \"192.0.2.100\"|clusterVip = \"$VIP\"|" "$file"
  fi
  if [[ -n "$BOOTSTRAP_IP" ]]; then
    # First ip = in the file is server0 in the example (bootstrap)
    sed -i "0,/ip = \"192.0.2.10\"/s|ip = \"192.0.2.10\"|ip = \"$BOOTSTRAP_IP\"|" "$file"
  fi
  if [[ -n "$AGENT_IP" ]]; then
    sed -i "s|ip = \"192.0.2.20\"|ip = \"$AGENT_IP\"|" "$file"
  fi
}

write_from_example() {
  [[ -f "$EXAMPLE" ]] || {
    echo "error: missing $EXAMPLE" >&2
    exit 1
  }
  if [[ -f "$TOPOLOGY" ]]; then
    local bak="${TOPOLOGY}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$TOPOLOGY" "$bak"
    echo "backed up existing topology → $bak"
  fi
  cp -a "$EXAMPLE" "$TOPOLOGY"
  patch_topology "$TOPOLOGY"
  echo "wrote $TOPOLOGY from example"
}

hint_nix
echo

if [[ "$SKIP_SOPS" -eq 0 ]]; then
  echo "=== sops / age (cluster token) ==="
  ./scripts/sops-bootstrap.sh
  echo
else
  echo "=== skipping sops-bootstrap (--skip-sops) ==="
  echo
fi

echo "=== topology ==="
if [[ "$FROM_EXAMPLE" -eq 1 ]]; then
  write_from_example
elif [[ ! -f "$TOPOLOGY" ]]; then
  echo "topology.nix missing — copying example"
  write_from_example
else
  echo "using existing topology (not overwritten): $TOPOLOGY"
  if [[ -n "$SSH_KEY$GATEWAY$VIP$BOOTSTRAP_IP$AGENT_IP" ]]; then
    echo "note: --ssh-key/--gateway/--vip/--*-ip only apply when writing from example" >&2
    echo "      re-run with --from-example to apply them (backs up first)." >&2
  fi
fi
echo

cat <<EOF
=== next steps (named 1+1 Proxmox) ===

1. Edit topology if needed: $TOPOLOGY
   - adminSshKeys, gateway, clusterVip, node ips
2. Proxmox API env: see docs/proxmox-rbac.md
3. Bake (Nix or nix-docker; qcow2 needs KVM):
     nix build .#packages.x86_64-linux.proxmox-server0-qcow2 --out-link result-server-qcow
     nix build .#packages.x86_64-linux.proxmox-agent0-qcow2 --out-link result-agent-qcow
4. Import (pick free VMIDs; CP memory ≥3072):
     PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh ./result-server-qcow/nixos.qcow2 200
     ./scripts/proxmox-import.sh ./result-agent-qcow/nixos.qcow2 201
5. Attach age key before first boot:
     ./scripts/proxmox-age-cloudinit.sh 200 201
6. Start server0, then agent0; kubectl get nodes on server0

Success checklist + full walkthrough: docs/getting-started.md
Author lab reference (this repo's fleet): docs/lab.md
EOF
