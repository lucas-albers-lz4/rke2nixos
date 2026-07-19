# Control-plane rebuild / etcd membership (R6)

Once you run three servers, etcd quorum is real. Node replacement is not
"reinstall and hope" — membership must be cleaned up from a surviving CP.

Join URL: prefer cluster VIP (`settings.clusterVip`, currently `192.168.1.29`) when keepalived is enabled; sticky `bootstrapHost` remains valid. Avoid `192.168.1.20` on this LAN (conflicts with another device).

## Grow to quorum

Configs: `proxmox-server1` / `proxmox-server2` (or QEMU `example-server1` / `example-server2`).

1. server0 healthy (Ready)
2. Join server1 with same sops token and `joinUrl = "https://<server0-ip>:9345"`
3. Join server2 likewise
4. Confirm three Ready control-plane nodes:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes -l node-role.kubernetes.io/control-plane
```

Automated coverage: `nix build .#checks.x86_64-linux.three-server` (Linux + KVM).

## Drill: replace a non-last control-plane node

Practice once on a **non-bootstrap** CP (e.g. server2) while server0+server1 stay up.

1. Drain / cordon if the node is still reachable:

   ```bash
   kubectl cordon server2
   kubectl drain server2 --ignore-daemonsets --delete-emptydir-data
   ```

2. On a **surviving** server, remove the Kubernetes node and etcd member:

   ```bash
   kubectl delete node server2

   export C=/var/lib/rancher/rke2/server/tls/etcd
   ETCDCTL_API=3 etcdctl \
     --cacert="$C/server-ca.crt" \
     --cert="$C/server-client.crt" \
     --key="$C/server-client.key" \
     member list

   # note the member ID for server2, then:
   ETCDCTL_API=3 etcdctl \
     --cacert="$C/server-ca.crt" \
     --cert="$C/server-client.crt" \
     --key="$C/server-client.key" \
     member remove <member-id>
   ```

   (`etcdctl` may live under an RKE2 containerd snapshot, e.g.
   `find /var/lib/rancher/rke2 -name etcdctl -type f`, or install via `nix-shell -p etcd`.)

3. Wipe or reprovision the machine (clear `/var/lib/rancher/rke2` on the replaced node only).

4. Rejoin with the **same** cluster token and `joinUrl`.

5. Uncordon when Ready.

## Hard rules

- Do **NOT** rebuild the last remaining server without an etcd backup + restore plan.
- Never regenerate the cluster token after first bootstrap.
- Prefer practicing this drill on Proxmox (fast re-image) before bare metal.

## R6 success criteria

- Three CP nodes Ready on a real or QEMU cluster
- One successful non-last CP replace drill documented for your environment
