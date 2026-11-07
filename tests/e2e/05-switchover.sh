#!/usr/bin/env bash
# Planned switchover under write load, the way maintenance (node drain,
# operator-driven rolling update, manual promote) moves the primary.
# Expect a much shorter outage than a failover and, again, no lost writes.
source "$(dirname "$0")/lib.sh"

DURATION=${DURATION:-60}
SWITCH_AFTER=${SWITCH_AFTER:-15}
LOG=/tmp/switchover-writer.log

command -v kubectl-cnpg >/dev/null || fail "kubectl cnpg plugin not installed"

wait_ready 10m
old_primary=$(primary)
target=$(kubectl -n "$NS" get pods -l "cnpg.io/cluster=$PG_CLUSTER,cnpg.io/instanceRole=replica" \
  -o jsonpath='{.items[0].metadata.name}')

log "writer: one insert every 100ms through the rw pooler for ${DURATION}s"
start_writer switchover-writer switchover_check "$DURATION"
sleep "$SWITCH_AFTER"

log "switchover $old_primary -> $target"
t_switch=$(date +%s.%N)
kubectl cnpg promote "$PG_CLUSTER" "$target" -n "$NS"
t_promoted=$(wait_promotion "$old_primary")

finish_writer switchover-writer "$DURATION" "$LOG"
wait_ready 10m

log "results"
echo "primary:  $old_primary -> $(primary)"
writer_report "$LOG" switchover_check "$t_switch" "$t_promoted"

[[ $(primary) == "$target" ]] || fail "primary is $(primary), want $target"
[[ $LOST == 0 ]] || fail "$LOST acknowledged writes lost"
awk -v g="$GAP" 'BEGIN { exit !(g < 30) }' || fail "write downtime ${GAP}s"

log "old primary is a streaming replica again"
kubectl -n "$NS" wait "pod/$old_primary" --for=condition=Ready --timeout=5m
role=$(kubectl -n "$NS" get pod "$old_primary" -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}')
[[ $role == replica ]] || fail "$old_primary role is $role"
states=$(psql_primary -c "select sync_state from pg_stat_replication where state = 'streaming'" | sort | uniq -c | xargs)
[[ $states == "2 quorum" ]] || fail "replication after switchover: $states"

echo "PASS 05-switchover"
