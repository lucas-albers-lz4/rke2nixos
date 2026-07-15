# Control-plane rebuild / etcd membership notes (phase 1.5+)
#
# Once you run three servers, etcd quorum is real. Node replacement is not
# "reinstall and hope" — membership must be cleaned up from a surviving CP.
#
# Procedure to replace a non-last control-plane node:
#   1. Drain / cordon if the node is still reachable
#   2. On a surviving server:
#        kubectl delete node <name>
#        # remove etcd member via rke2 etcd-snapshot / etcdctl as appropriate
#        # (member list uses local etcd certs under /var/lib/rancher/rke2/server/tls/etcd/)
#   3. Wipe or reprovision the machine (clear /var/lib/rancher/rke2)
#   4. Rejoin with the SAME cluster token and joinUrl
#   5. Uncordon when Ready
#
# Do NOT rebuild the last remaining server without an etcd backup + restore plan.
#
# Join URL in this flake stays sticky to server0:9345 until a VIP/LB is introduced.
