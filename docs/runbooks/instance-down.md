# Instance down, no primary, standby missing

## Triage

```bash
kubectl cnpg status orders-db -n orders
kubectl -n orders get pods -l cnpg.io/cluster=orders-db -o wide
kubectl -n orders get events --sort-by=.lastTimestamp | tail -30
```

## No primary (critical)

The operator normally promotes a standby within seconds (about 20 s in the
failover test). If it has not:

1. Is the operator running? `kubectl -n cnpg-system get pods`. A dead
   operator cannot fail over; restart it first.
2. Read the operator log for this cluster:
   `kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg | grep orders-db | tail -50`.
3. If the old primary's node is `NotReady` but the pod is not gone, the
   operator may be waiting on it. Confirm the node is really down (cloud
   console), then delete the pod with `--grace-period=0 --force`.
4. Manual promotion, only with a healthy standby:
   `kubectl cnpg promote orders-db orders-db-2 -n orders`.

Clients reconnect through the pooler without any change.

## Instance down / standby missing

- **Pending:** usually the required zone anti-affinity with a zone down, or
  the PVC bound to a zone with no capacity. `kubectl describe pod` shows
  which. Do not relax the anti-affinity to get it scheduled (ADR 0002).
- **CrashLoopBackOff:** `kubectl -n orders logs <pod> -c postgres --previous`.
  A standby that cannot rejoin after a failover is usually a timeline
  divergence that `pg_rewind` could not fix: delete its PVCs and pod
  (`kubectl cnpg destroy orders-db <instance> -n orders`) and the operator
  rebuilds it from the primary.

While a standby is missing the cluster has no spare for quorum commit; with
`dataDurability: preferred` it stays writable but one more loss can lose
acknowledged writes. Treat it as urgent.
