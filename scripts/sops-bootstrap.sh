#!/usr/bin/env bash
# Bootstrap age + sops for this repo.
# Usage: ./scripts/sops-bootstrap.sh
#        ./scripts/sops-bootstrap.sh --rotate-token
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AGE_KEY="${SOPS_AGE_KEY_FILE:-$ROOT/secrets/age.key}"
ENC="$ROOT/secrets/rke2-token.enc.yaml"
PLAIN="$ROOT/secrets/rke2-token.yaml"

run_with_sops() {
  if command -v sops >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
    "$@"
  else
    export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes
warn-dirty = false}"
    nix shell nixpkgs#sops nixpkgs#age -c "$@"
  fi
}

if [[ ! -f "$AGE_KEY" ]]; then
  mkdir -p "$(dirname "$AGE_KEY")"
  run_with_sops age-keygen -o "$AGE_KEY"
  chmod 600 "$AGE_KEY"
  echo "wrote $AGE_KEY"
fi

PUB="$(grep '# public key:' "$AGE_KEY" | sed 's/.*: //')"

# Keep root .sops.yaml and secrets/.sops.yaml in sync for docs that link either path.
for cfg in "$ROOT/.sops.yaml" "$ROOT/secrets/.sops.yaml"; do
  cat >"$cfg" <<EOF
# Age recipients — admin key decrypts cluster secrets at deploy time.
# Private key: secrets/age.key (gitignored) or \$SOPS_AGE_KEY_FILE.
# Generate a replacement: ./scripts/sops-bootstrap.sh
keys:
  - &admin $PUB

creation_rules:
  - path_regex: secrets/[^/]+\\.(yaml|yml|json|env)\$
    key_groups:
      - age:
          - *admin
EOF
done

if [[ "${1:-}" == "--rotate-token" ]] || [[ ! -f "$PLAIN" ]]; then
  TOKEN="rke2-$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)"
  cat >"$PLAIN" <<EOF
# Plaintext source (gitignored). Encrypt with: ./scripts/sops-bootstrap.sh
# IMPORTANT: reuse forever after first bootstrap — rotating breaks joins/rebuilds.
rke2-token: $TOKEN
EOF
  echo "wrote $PLAIN"
fi

export SOPS_AGE_KEY_FILE="$AGE_KEY"
cp "$PLAIN" "$ENC"
run_with_sops sops -e -i "$ENC"
echo "encrypted $ENC"
echo
echo "Next:"
echo "  1. Keep $AGE_KEY private (gitignored)."
echo "  2. On each deploy node: install the private key at /var/lib/sops-nix/key.txt"
echo "  3. Decrypt check: SOPS_AGE_KEY_FILE=$AGE_KEY sops -d $ENC"
