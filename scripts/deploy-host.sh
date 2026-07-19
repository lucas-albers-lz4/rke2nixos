#!/usr/bin/env bash
# Day-2 deploy: nixos-rebuild switch against a live host without wiping RKE2 state.
# Usage:
#   ./scripts/deploy-host.sh proxmox-server0 root@10.0.0.10
#   ./scripts/deploy-host.sh bare-metal-agent0 root@10.0.0.20
#
# Requires: SSH access, secrets/age.key (or SOPS_AGE_KEY_FILE) for sops-backed hosts,
# and the same age private key already present on the target at /var/lib/sops-nix/key.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:?usage: $0 <nixosConfiguration> <user@host>}"
TARGET="${2:?usage: $0 <nixosConfiguration> <user@host>}"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$ROOT/secrets/age.key}"

if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
  echo "warning: $SOPS_AGE_KEY_FILE missing — sops-backed hosts will fail to decrypt" >&2
fi

echo "Deploying flake config '$CONFIG' → $TARGET"
echo "RKE2 state under /var/lib/rancher/rke2 is left intact across generations."

rebuild=(nixos-rebuild)
if ! command -v nixos-rebuild >/dev/null 2>&1; then
  # Workstation may only have the nix CLI (common with Determinate / multi-user nix).
  rebuild=(nix shell nixpkgs#nixos-rebuild -c nixos-rebuild)
fi

exec "${rebuild[@]}" switch \
  --flake "$ROOT#$CONFIG" \
  --target-host "$TARGET" \
  --use-remote-sudo
