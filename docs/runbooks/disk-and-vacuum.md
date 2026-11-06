# Disk filling up, transaction ID age

## Which volume?

Data and WAL are separate PVCs (`orders-db-N` and `orders-db-N-wal`).

- **WAL volume filling:** almost always WAL that cannot be removed. Check,
  in order: archiving stuck ([backup-failing](backup-failing.md)), an
  inactive replication slot, a very long transaction.

  ```bash
  kubectl cnpg psql orders-db -n orders -- -c "select slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) from pg_replication_slots"
  ```

- **Data volume filling:** growth or bloat. Expand online (both AKS
  `managed-csi-premium` and EKS `gp3` allow volume expansion) by raising
  `spec.storage.size` in the overlay; the operator resizes each PVC.

Never delete files from `pg_wal` by hand.

## Transaction ID age

Postgres must freeze old rows before XID age reaches about 2.1 billion, or it
stops accepting writes. Autovacuum normally handles this at 200 million. An
age over 1 billion means something is blocking freezing:

```bash
kubectl cnpg psql orders-db -n orders -- -c "select datname, age(datfrozenxid) from pg_database order by 2 desc"
kubectl cnpg psql orders-db -n orders -- -c "select relname, age(relfrozenxid) from pg_class where relkind = 'r' order by 2 desc limit 10"
```

Blockers: long transactions, abandoned replication slots, prepared
transactions (`pg_prepared_xacts`). Remove the blocker, then
`vacuum (freeze, verbose)` the oldest tables.
