#!/usr/bin/env bash
# Clients reach Postgres through PgBouncer only, and only from the team's
# namespaces.
source "$(dirname "$0")/lib.sh"

app_pw=$(secret_value "$PG_CLUSTER-app" password)
ro_pw=$(secret_value orders-db-readonly password)
rw="host=$PG_CLUSTER-pooler-rw.$NS.svc dbname=orders user=orders"
ro="host=$PG_CLUSTER-pooler-ro.$NS.svc dbname=orders user=orders_readonly"
direct="host=$PG_CLUSTER-rw.$NS.svc dbname=orders user=orders"

client_namespace orders-app orders
client_namespace other-team none

log "pooler deployments ready, one pod per zone"
for p in rw ro; do
  kubectl -n "$NS" rollout status "deploy/$PG_CLUSTER-pooler-$p" --timeout=3m
  n=$(kubectl -n "$NS" get pods -l "cnpg.io/poolerName=$PG_CLUSTER-pooler-$p" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')
  [[ $n == 2 ]] || fail "pooler-$p pods on $n nodes, want 2"
done

log "read-write pooler reaches the primary"
out=$(client orders-app "$app_pw" psql -qtAX "$rw" -c "
  create table if not exists pooler_check (id int);
  insert into pooler_check values (1);
  select pg_is_in_recovery();")
[[ $out == f ]] || fail "rw pooler: $out"

log "read-only pooler reaches a standby"
out=$(client orders-app "$ro_pw" psql -qtAX "$ro" -c "select pg_is_in_recovery()")
[[ $out == t ]] || fail "ro pooler: $out"

log "direct connection to Postgres is blocked, even from the team namespace"
if client orders-app "$app_pw" psql -qtAX "$direct" -c "select 1" 2>/dev/null; then
  fail "direct connection to $PG_CLUSTER-rw succeeded"
fi

log "another team's namespace cannot reach the pooler"
if client other-team "$app_pw" psql -qtAX "$rw" -c "select 1" 2>/dev/null; then
  fail "connection from other-team succeeded"
fi

log "200 clients share the pool"
client orders-app "$app_pw" pgbench -h "$PG_CLUSTER-pooler-rw.$NS.svc" -U orders orders \
  -i -s 1 -q >/dev/null 2>&1
client orders-app "$app_pw" pgbench -h "$PG_CLUSTER-pooler-rw.$NS.svc" -U orders orders \
  -c 200 -j 4 -T 15 -S -n 2>&1 | grep -E "^(number of failed|tps)"
servers=$(psql_primary -c "select count(*) from pg_stat_activity where usename = 'orders' and backend_type = 'client backend'")
echo "server connections from the pooler: $servers"
# Two pooler pods x (default_pool_size 20 + reserve_pool_size 5).
(( servers <= 50 )) || fail "$servers server connections for 200 clients"

echo "PASS 02-pooler"
