# Secrets

| File | Purpose |
|------|---------|
| `age.key` | Private age key (**gitignored**) — also used as `SOPS_AGE_KEY_FILE` |
| `rke2-token.yaml` | Plaintext cluster/server token source (**gitignored**) |
| `rke2-token.enc.yaml` | Encrypted cluster token (committed) — CP + named agents |
| `rke2-agent-token.yaml` | Plaintext agent join token (**gitignored**) — golden workers |
| `rke2-agent-token.enc.yaml` | Encrypted agent token (committed) — golden image only |
| `.sops.yaml` | Age recipients (mirrors repo-root `.sops.yaml`) |

```bash
./scripts/sops-bootstrap.sh
./scripts/sops-bootstrap.sh --agent-token   # or --agent-token --from-cluster-token (lab)
sops -d secrets/rke2-token.enc.yaml
sops -d secrets/rke2-agent-token.enc.yaml
# On each node: install age.key as /var/lib/sops-nix/key.txt
```

Never commit `age.key`. Never rotate the cluster token after first bootstrap. Prefer a dedicated RKE2 agent-token for golden workers (separate from the server token).
