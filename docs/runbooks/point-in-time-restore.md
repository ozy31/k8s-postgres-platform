# Point-in-time restore

Restore into a new cluster next to `orders-db` (ADR 0004). The e2e test
`tests/e2e/03-backup-restore.sh` runs this exact procedure on every CI run.

1. Find the time to restore to, in UTC, just before the bad change:
   from the application log, or `pg_stat_statements`, or the audit trail.
2. Check it is recoverable: it must be after the first recoverability point.

   ```bash
   kubectl -n orders get objectstore orders-db-backups -o jsonpath='{.status.serverRecoveryWindow}'
   ```

3. Create the restore cluster:

   ```bash
   sed "s/TARGET_TIME/2026-11-06T09:15:00Z/" postgres/restore/orders-db-restore.yaml | kubectl -n orders apply -f -
   kubectl -n orders wait cluster/orders-db-restore --for=condition=Ready --timeout=60m
   ```

4. Compare and copy back what was lost, for example with `pg_dump -t` from
   the restore and `psql` into `orders-db` (through the rw pooler).
5. If `orders-db` itself is unusable instead: scale the application to
   zero, point the poolers at the restored cluster
   (`spec.cluster.name: orders-db-restore` on both `Pooler`s), scale it up
   to three instances, enable the backup plugin on it, take a base backup,
   and scale the application back.
6. Delete the restore cluster when done:
   `kubectl -n orders delete cluster orders-db-restore`.

Restore time scales with the base backup size plus the WAL to replay since
it. On kind with a tiny database it takes about a minute; for a 200 GB
database plan for tens of minutes, and keep base backups daily so replay
stays short.
