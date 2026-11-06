# Backups and WAL archiving

PITR is only as good as the last archived WAL segment. Archiving stuck is
critical; an old base backup is a warning (WAL still covers it, but restores
get slower and retention may be at risk).

## Triage

```bash
kubectl cnpg status orders-db -n orders                 # "Continuous Backup status"
kubectl -n orders get backup --sort-by=.metadata.creationTimestamp | tail
kubectl -n orders logs <primary> -c plugin-barman-cloud --tail=100
kubectl -n orders get objectstore orders-db-backups -o yaml   # status: first recoverability point
```

## Common causes

| Symptom in the sidecar log | Cause | Fix |
|---|---|---|
| `AccessDenied` / `AuthorizationPermissionMismatch` | identity lost its role, or federated credential subject wrong | AKS: `Storage Blob Data Contributor` on the container, subject `system:serviceaccount:orders:orders-db`. EKS: Pod Identity association for `orders/orders-db` |
| `NoSuchBucket` / `ContainerNotFound` | bucket/container deleted or renamed | recreate; then take a new base backup |
| timeouts | egress blocked (NetworkPolicy, firewall, private endpoint DNS) | test from the pod: `kubectl exec <primary> -c postgres -- curl -sI <endpoint>` |
| `requested plugin is not available` on a Backup | Backup created before the sidecar was running (first deploy) | ignore if later backups complete; `kubectl -n orders delete backup <name>` |

After fixing, force a segment switch and confirm it is archived:

```bash
kubectl cnpg psql orders-db -n orders -- -c "select pg_switch_wal()"
kubectl cnpg psql orders-db -n orders -- -c "select last_archived_wal, last_failed_wal from pg_stat_archiver"
kubectl cnpg backup orders-db -n orders --method plugin --plugin-name barman-cloud.cloudnative-pg.io
```

WAL that could not be archived stays in `pg_wal` on the primary, so a long
outage also fills the WAL volume: watch `PostgresVolumeFillingUp`.
