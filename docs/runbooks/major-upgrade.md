# Major version upgrade (for example 17 to 18)

CloudNativePG (1.26+) upgrades in place when `imageName` moves to a newer
major: it shuts the cluster down, runs `pg_upgrade` in a job on the primary's
volume, then recreates the standbys from the upgraded primary. **The
cluster is unavailable for the duration**; plan a maintenance window.

[`tests/e2e/06-major-upgrade.sh`](../../tests/e2e/06-major-upgrade.sh) runs
this procedure on every CI build: a two-instance cluster on 17.9 with 10,000
rows, `imageName` switched to 18.6, then version, a checksum of the data and
streaming replication are checked. On kind the whole upgrade took 67 s; the
time grows with the database size (pg_upgrade) and the standby rebuild.

## Before

1. Read the release notes for removed features and changed defaults.
2. Restore last night's backup into a scratch cluster and upgrade *that*
   first (`postgres/restore`, then change its `imageName`). Time it; that
   is the downtime to expect.
3. Check extensions exist for the new major in the target image.
4. Take a fresh base backup right before:
   `kubectl cnpg backup orders-db -n orders --method plugin --plugin-name barman-cloud.cloudnative-pg.io`.

## Upgrade

Change `imageName` in `postgres/base/cluster.yaml` (for example
`...:17.9-minimal-trixie` to `...:18.6-minimal-trixie`) and apply.

```bash
kubectl -n orders get cluster orders-db -w
kubectl -n orders get jobs -l cnpg.io/cluster=orders-db
```

## After

- `kubectl cnpg psql orders-db -n orders -- -c "select version()"`
- Planner statistics are not carried over: run `vacuumdb --all --analyze-in-stages`
  from the primary before taking full traffic.
- Take a new base backup; WAL from the old major cannot be replayed onto
  the new one.

## Rollback

There is no in-place downgrade. Roll back by restoring the pre-upgrade backup
into a new cluster on the old image (point-in-time-restore runbook) and
pointing the poolers at it.
