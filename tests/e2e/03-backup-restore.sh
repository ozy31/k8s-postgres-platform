#!/usr/bin/env bash
# Base backup to object storage, continuous WAL archiving, and a
# point-in-time restore to just before an accidental DELETE.
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/../.."

RESTORE=$PG_CLUSTER-restore
cleanup() { kubectl -n "$NS" delete cluster "$RESTORE" --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

log "WAL archiving is healthy"
kubectl -n "$NS" wait "cluster/$PG_CLUSTER" --for=condition=ContinuousArchiving --timeout=5m

log "on-demand base backup"
backup=$PG_CLUSTER-e2e-$(date +%s)
kubectl -n "$NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup
spec:
  cluster:
    name: $PG_CLUSTER
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
YAML
kubectl -n "$NS" wait "backup/$backup" --for=jsonpath='{.status.phase}'=completed --timeout=10m

log "write 1000 rows, note the time, then delete them by mistake"
psql_primary -c "drop table if exists pitr_check; create table pitr_check as select g as id from generate_series(1, 1000) g;"
target=$(psql_primary -c "select to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
sleep 2
psql_primary -c "delete from pitr_check"
echo "target time: $target"

log "close the current WAL segment and wait for it to be archived"
segment=$(psql_primary -c "select pg_walfile_name(pg_switch_wal())")
for _ in $(seq 60); do
  archived=$(psql_primary -c "select coalesce(last_archived_wal, '') from pg_stat_archiver")
  [[ $archived > $segment || $archived == "$segment" ]] && break
  sleep 2
done
echo "segment $segment, last archived $archived"
[[ $archived > $segment || $archived == "$segment" ]] || fail "WAL $segment not archived"

log "restore to $target in a new cluster"
sed "s/TARGET_TIME/$target/" postgres/restore/orders-db-restore.yaml | kubectl -n "$NS" apply -f -
start=$(date +%s)
kubectl -n "$NS" wait "cluster/$RESTORE" --for=condition=Ready --timeout=10m
echo "restore took $(( $(date +%s) - start ))s"

log "the deleted rows are back in the restored cluster"
restored_primary=$(kubectl -n "$NS" get pods -l "cnpg.io/cluster=$RESTORE,cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
rows=$(kubectl -n "$NS" exec "$restored_primary" -c postgres -- psql -qtAX -d orders -c "select count(*) from pitr_check")
echo "rows in restore: $rows, rows in orders-db: $(psql_primary -c 'select count(*) from pitr_check')"
[[ $rows == 1000 ]] || fail "restored $rows rows, want 1000"

echo "PASS 03-backup-restore"
