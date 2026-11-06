#!/usr/bin/env bash
# The cluster is up, spread over three zones, and replicating with quorum
# commit.
source "$(dirname "$0")/lib.sh"

log "waiting for $PG_CLUSTER"
wait_ready

log "one instance per zone"
zones=$(kubectl -n "$NS" get pods -l "cnpg.io/cluster=$PG_CLUSTER,cnpg.io/podRole=instance" \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' |
  xargs -I{} kubectl get node {} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}' |
  sort -u | wc -l | tr -d ' ')
[[ $zones == 3 ]] || fail "instances span $zones zones, want 3"

log "two quorum standbys streaming"
states=$(psql_primary -c "select sync_state from pg_stat_replication where state = 'streaming'" | sort | uniq -c | xargs)
echo "$states"
[[ $states == "2 quorum" ]] || fail "replication: $states"

log "synchronous_standby_names uses ANY 1"
ssn=$(psql_primary -c "show synchronous_standby_names")
echo "$ssn"
[[ $ssn == ANY\ 1* ]] || fail "synchronous_standby_names=$ssn"

log "pg_stat_statements installed by the Database resource"
ext=$(psql_primary -c "select count(*) from pg_extension where extname = 'pg_stat_statements'")
[[ $ext == 1 ]] || fail "pg_stat_statements missing"

log "managed read-only role can log in and cannot write"
pw=$(kubectl -n "$NS" get secret orders-db-readonly -o jsonpath='{.data.password}' | base64 -d)
ro() {
  kubectl -n "$NS" exec "$(primary)" -c postgres -- env PGPASSWORD="$pw" \
    psql -qtAX "host=localhost dbname=orders user=orders_readonly" "$@"
}
ro -c "select 1" >/dev/null || fail "orders_readonly cannot log in"
if ro -c "create table ro_write_test (id int)" 2>/dev/null; then
  fail "orders_readonly was able to create a table"
fi

echo "PASS 01-cluster"
