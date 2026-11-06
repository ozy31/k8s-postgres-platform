#!/usr/bin/env bash
# Kill the primary under write load. Measures how long writes through the
# pooler fail, and checks that every write the client saw acknowledged is
# still there afterwards (quorum commit means no acknowledged loss).
source "$(dirname "$0")/lib.sh"

DURATION=${DURATION:-90}
KILL_AFTER=${KILL_AFTER:-20}
WRITER=failover-writer

client_namespace orders-app orders
app_pw=$(secret_value "$PG_CLUSTER-app" password)
rw="host=$PG_CLUSTER-pooler-rw.$NS.svc dbname=orders user=orders"

wait_ready
psql_primary -c "drop table if exists failover_check; create table failover_check (id int primary key, at timestamptz default clock_timestamp()); grant all on failover_check to orders;"
old_primary=$(primary)

log "writer: one insert every 100ms through the rw pooler for ${DURATION}s"
kubectl -n orders-app delete pod "$WRITER" --ignore-not-found --wait >/dev/null
# shellcheck disable=SC2016 # expanded inside the pod, not here
kubectl -n orders-app run "$WRITER" --restart=Never --image="$PG_IMAGE" \
  --env="PGPASSWORD=$app_pw" --env="PGCONNECT_TIMEOUT=3" --env="RW=$rw" --env="DURATION=$DURATION" \
  --command -- bash -c '
    end=$(( $(date +%s) + DURATION )); i=0
    while (( $(date +%s) < end )); do
      i=$((i + 1))
      if psql -qtAX "$RW" -c "set statement_timeout = 5000; insert into failover_check (id) values ($i)" >/dev/null 2>&1; then
        echo "$(date +%s.%N) ok $i"
      else
        echo "$(date +%s.%N) fail $i"
      fi
      sleep 0.1
    done'
kubectl -n orders-app wait "pod/$WRITER" --for=condition=Ready --timeout=2m

sleep "$KILL_AFTER"
log "force-deleting the primary $old_primary"
kubectl -n "$NS" delete pod "$old_primary" --grace-period=0 --force 2>/dev/null

kubectl -n orders-app wait "pod/$WRITER" --for=jsonpath='{.status.phase}'=Succeeded --timeout=$((DURATION + 60))s
kubectl -n orders-app logs "$WRITER" > /tmp/failover-writer.log
kubectl -n orders-app delete pod "$WRITER" --wait=false >/dev/null

wait_ready
new_primary=$(primary)

log "results"
ok=$(grep -c ' ok ' /tmp/failover-writer.log || true)
failed=$(grep -c ' fail ' /tmp/failover-writer.log || true)
# Longest gap between two acknowledged writes = how long writes were down.
gap=$(awk '$2 == "ok" { if (prev) { d = $1 - prev; if (d > max) max = d } prev = $1 } END { printf "%.1f", max }' /tmp/failover-writer.log)
echo "primary:  $old_primary -> $new_primary"
echo "writes:   $ok acknowledged, $failed failed"
echo "downtime: ${gap}s (longest gap between acknowledged writes)"

[[ $new_primary != "$old_primary" ]] || fail "primary did not change"
awk '$2 == "ok" { print $3 }' /tmp/failover-writer.log | sort -n > /tmp/acked
psql_primary -c "select id from failover_check order by id" | sort -n > /tmp/stored
lost=$(comm -23 /tmp/acked /tmp/stored | wc -l | tr -d ' ')
echo "lost:     $lost acknowledged writes missing after failover"
[[ $lost == 0 ]] || fail "$lost acknowledged writes lost"
awk -v g="$gap" 'BEGIN { exit !(g < 60) }' || fail "write downtime ${gap}s"

log "old primary rejoined as a replica"
kubectl -n "$NS" wait "pod/$old_primary" --for=condition=Ready --timeout=5m
role=$(kubectl -n "$NS" get pod "$old_primary" -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}')
[[ $role == replica ]] || fail "$old_primary role is $role"
states=$(psql_primary -c "select sync_state from pg_stat_replication where state = 'streaming'" | sort | uniq -c | xargs)
[[ $states == "2 quorum" ]] || fail "replication after failover: $states"

echo "PASS 04-failover"
