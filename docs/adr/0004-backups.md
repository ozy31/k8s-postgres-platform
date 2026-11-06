# 0004: Barman Cloud plugin, restore into a new cluster

**Status:** accepted

## Decision

- Backups go through the **Barman Cloud plugin** (CNPG-I), configured by an
  `ObjectStore` per environment. Not the in-tree
  `spec.backup.barmanObjectStore`, which upstream has deprecated in favour
  of the plugin.
- **WAL is archived continuously**; base backups run nightly and once at
  creation. Retention is 7 days locally, 14 in the cloud.
- **Credentials come from workload identity / Pod Identity** in the cloud.
  No storage keys in Secrets.
- **Restores go into a new cluster next to the original**
  ([`postgres/restore`](../../postgres/restore/orders-db-restore.yaml)),
  never over it.

## Why restore beside, not in place

A PITR is usually needed because of bad data, not a dead cluster. Restoring
beside the original lets the team compare, copy back the affected rows, and
keep every write that happened since. If the original really is lost,
the restored cluster is promoted by pointing the poolers at it.

## Verification

Backups that are never restored are a hope, not a backup. The e2e test
restores to a timestamp on every CI run, and the `PostgresBackupTooOld`,
`PostgresBackupFailed` and `PostgresWALArchivingStuck` alerts cover the
silent failures.

## Consequences

- The plugin runs as a sidecar in each instance pod and needs cert-manager
  for its mTLS with the operator.
- Backup age metrics come from the plugin
  (`barman_cloud_cloudnative_pg_io_*`); the operator's
  `cnpg_collector_*backup*` series stay at 0 with this setup.
