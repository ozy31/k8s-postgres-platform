#!/usr/bin/env bash
# Kill the primary under write load. Measures how long writes through the
# pooler fail, and checks that every write the client saw acknowledged is
# still there afterwards (quorum commit means no acknowledged loss).
source "$(dirname "$0")/lib.sh"

DURATION=${DURATION:-90}
KILL_AFTER=${KILL_AFTER:-20}
LOG=/tmp/failover-writer.log

wait_ready 10m
old_primary=$(primary)

log "writer: one insert every 100ms through the rw pooler for ${DURATION}s"
start_writer failover-writer failover_check "$DURATION"
sleep "$KILL_AFTER"

log "force-deleting the primary $old_primary"
t_kill=$(date +%s.%N)
kubectl -n "$NS" delete pod "$old_primary" --grace-period=0 --force 2>/dev/null
t_promoted=$(wait_promotion "$old_primary")

finish_writer failover-writer "$DURATION" "$LOG"
wait_ready 10m
new_primary=$(primary)

log "results"
echo "primary:  $old_primary -> $new_primary"
writer_report "$LOG" failover_check "$t_kill" "$t_promoted"

[[ $new_primary != "$old_primary" ]] || fail "primary did not change"
[[ $LOST == 0 ]] || fail "$LOST acknowledged writes lost"
awk -v g="$GAP" 'BEGIN { exit !(g < 60) }' || fail "write downtime ${GAP}s"

log "old primary rejoined as a replica"
kubectl -n "$NS" wait "pod/$old_primary" --for=condition=Ready --timeout=5m
role=$(kubectl -n "$NS" get pod "$old_primary" -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}')
[[ $role == replica ]] || fail "$old_primary role is $role"
states=$(psql_primary -c "select sync_state from pg_stat_replication where state = 'streaming'" | sort | uniq -c | xargs)
[[ $states == "2 quorum" ]] || fail "replication after failover: $states"

echo "PASS 04-failover"
