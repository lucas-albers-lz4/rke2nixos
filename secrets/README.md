# Secrets

| File | Purpose |
|------|---------|
| `age.key` | Private age key (**gitignored**) — also used as `SOPS_AGE_KEY_FILE` |
| `rke2-token.yaml` | Plaintext token source (**gitignored**) |
| `rke2-token.enc.yaml` | Encrypted token (committed) |
| `.sops.yaml` | Age recipients (mirrors repo-root `.sops.yaml`) |

```bash
./scripts/sops-bootstrap.sh
sops -d secrets/rke2-token.enc.yaml
# On each node: install age.key as /var/lib/sops-nix/key.txt
```

Never commit `age.key` or rotate the cluster token after first bootstrap.
