# Runbooks

Every alert in [`prometheusrule.yaml`](../../postgres/base/prometheusrule.yaml)
links to one of these. Commands assume the
[`cnpg` kubectl plugin](https://cloudnative-pg.io/documentation/current/kubectl-plugin/)
and namespace `orders`.

| Runbook | Alerts |
|---|---|
| [instance-down](instance-down.md) | PostgresInstanceDown, PostgresNoPrimary, PostgresStandbyMissing |
| [replication-lag](replication-lag.md) | PostgresReplicationLagHigh |
| [backup-failing](backup-failing.md) | PostgresWALArchivingStuck, PostgresBackupTooOld, PostgresBackupFailed |
| [connections](connections.md) | PostgresConnectionsNearLimit, PgBouncerClientsWaiting, PostgresLongTransaction |
| [disk-and-vacuum](disk-and-vacuum.md) | PostgresVolumeFillingUp, PostgresTransactionIDAgeHigh |
| [point-in-time-restore](point-in-time-restore.md) | (procedure) |
| [major-upgrade](major-upgrade.md) | (procedure) |

First command for anything:

```bash
kubectl cnpg status orders-db -n orders --verbose
```
