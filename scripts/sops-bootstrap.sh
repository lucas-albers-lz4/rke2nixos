#!/usr/bin/env bash
# Bootstrap age + sops for this repo.
# Usage: ./scripts/sops-bootstrap.sh
#        ./scripts/sops-bootstrap.sh --rotate-token
#        ./scripts/sops-bootstrap.sh --agent-token   # create/encrypt golden agent join token
#        ./scripts/sops-bootstrap.sh --agent-token --from-cluster-token  # lab: copy cluster token value
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AGE_KEY="${SOPS_AGE_KEY_FILE:-$ROOT/secrets/age.key}"
ENC="$ROOT/secrets/rke2-token.enc.yaml"
PLAIN="$ROOT/secrets/rke2-token.yaml"
AGENT_ENC="$ROOT/secrets/rke2-agent-token.enc.yaml"
AGENT_PLAIN="$ROOT/secrets/rke2-agent-token.yaml"

run_with_sops() {
  if command -v sops >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
    "$@"
  else
    export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes
warn-dirty = false}"
    nix shell nixpkgs#sops nixpkgs#age -c "$@"
  fi
}

encrypt_file() {
  local plain="$1" enc="$2"
  export SOPS_AGE_KEY_FILE="$AGE_KEY"
  cp "$plain" "$enc"
  run_with_sops sops -e -i "$enc"
  echo "encrypted $enc"
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

MODE="cluster"
FROM_CLUSTER=0
for arg in "$@"; do
  case "$arg" in
    --agent-token) MODE="agent" ;;
    --from-cluster-token) FROM_CLUSTER=1 ;;
    --rotate-token) MODE="cluster-rotate" ;;
    -h|--help)
      sed -n '2,7p' "$0"
      exit 0
      ;;
  esac
done

if [[ "$MODE" == "agent" ]]; then
  if [[ "$FROM_CLUSTER" == "1" ]]; then
    [[ -f "$PLAIN" ]] || {
      echo "error: $PLAIN missing — run ./scripts/sops-bootstrap.sh first, or decrypt $ENC" >&2
      exit 1
    }
    # Lab convenience only: same secret value, separate sops file so golden
    # images never import the server-token module path.
    TOKEN="$(grep -E '^rke2-token:' "$PLAIN" | sed 's/^rke2-token:[[:space:]]*//')"
    [[ -n "$TOKEN" ]] || {
      echo "error: could not read rke2-token from $PLAIN" >&2
      exit 1
    }
  elif [[ -n "${RKE2_AGENT_TOKEN:-}" ]]; then
    TOKEN="$RKE2_AGENT_TOKEN"
  elif [[ ! -f "$AGENT_PLAIN" ]]; then
    TOKEN="rke2-agent-$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)"
  else
    TOKEN="$(grep -E '^rke2-agent-token:' "$AGENT_PLAIN" | sed 's/^rke2-agent-token:[[:space:]]*//' || true)"
    [[ -n "$TOKEN" ]] || TOKEN="rke2-agent-$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)"
  fi
  cat >"$AGENT_PLAIN" <<EOF
# Plaintext agent join token (gitignored). Encrypt with: ./scripts/sops-bootstrap.sh --agent-token
# Prefer a dedicated RKE2 agent-token (not the server token) on production clusters.
# Lab: ./scripts/sops-bootstrap.sh --agent-token --from-cluster-token
rke2-agent-token: $TOKEN
EOF
  chmod 600 "$AGENT_PLAIN"
  echo "wrote $AGENT_PLAIN"
  encrypt_file "$AGENT_PLAIN" "$AGENT_ENC"
  echo
  echo "Next (golden agents):"
  echo "  1. On control planes, set the same value as RKE2 agent-token if it differs from the server token."
  echo "  2. Golden image uses hosts/sops-agent-token.nix only (never the server-token file)."
  echo "  3. Decrypt check: SOPS_AGE_KEY_FILE=$AGE_KEY sops -d $AGENT_ENC"
  exit 0
fi

if [[ "$MODE" == "cluster-rotate" ]] || [[ ! -f "$PLAIN" ]]; then
  TOKEN="rke2-$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)"
  cat >"$PLAIN" <<EOF
# Plaintext source (gitignored). Encrypt with: ./scripts/sops-bootstrap.sh
# IMPORTANT: reuse forever after first bootstrap — rotating breaks joins/rebuilds.
rke2-token: $TOKEN
EOF
  echo "wrote $PLAIN"
fi

encrypt_file "$PLAIN" "$ENC"
echo
echo "Next:"
echo "  1. Keep $AGE_KEY private (gitignored)."
echo "  2. On each deploy node: install the private key at /var/lib/sops-nix/key.txt"
echo "  3. Decrypt check: SOPS_AGE_KEY_FILE=$AGE_KEY sops -d $ENC"
echo "  4. Golden agents: ./scripts/sops-bootstrap.sh --agent-token"
