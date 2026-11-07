#!/usr/bin/env bash
# Shared helpers for the end-to-end tests.
set -euo pipefail

NS=${NS:-orders}
PG_CLUSTER=${PG_CLUSTER:-orders-db}

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

primary() {
  kubectl -n "$NS" get pods -l "cnpg.io/cluster=$PG_CLUSTER,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}'
}

# psql on the current primary as the postgres superuser (local socket).
psql_primary() {
  kubectl -n "$NS" exec "$(primary)" -c postgres -- psql -qtAX -d "${DB:-orders}" "$@"
}

wait_ready() {
  kubectl -n "$NS" wait "cluster/$PG_CLUSTER" --for=condition=Ready --timeout="${1:-10m}"
}

PG_IMAGE=${PG_IMAGE:-ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie}

# Namespace for test clients; labelled as the orders team unless told not to.
client_namespace() {
  local ns=$1 team=${2:-orders}
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if [[ $team == none ]]; then
    kubectl label namespace "$ns" team- >/dev/null 2>&1 || true
  else
    kubectl label namespace "$ns" team="$team" --overwrite >/dev/null
  fi
}

secret_value() {
  kubectl -n "$NS" get secret "$1" -o jsonpath="{.data.$2}" | base64 -d
}

# Runs a command in a throwaway Postgres client pod.
# usage: client <namespace> <password> <command...>
client() {
  local ns=$1 pw=$2
  shift 2
  kubectl -n "$ns" run "client-$RANDOM" --rm -i --quiet --restart=Never \
    --image="$PG_IMAGE" --env="PGPASSWORD=$pw" --env="PGCONNECT_TIMEOUT=5" \
    --command -- "$@"
}

# --- Write load for failover / switchover tests -----------------------------

# Starts a pod in orders-app that inserts one row every 100ms through the rw
# pooler and logs "<epoch> ok|fail <id>" per attempt.
# usage: start_writer <pod-name> <table> <duration-seconds>
start_writer() {
  local name=$1 table=$2 duration=$3 pw
  client_namespace orders-app orders
  pw=$(secret_value "$PG_CLUSTER-app" password)
  psql_primary -c "drop table if exists $table; create table $table (id int primary key, at timestamptz default clock_timestamp()); grant all on $table to orders;"
  kubectl -n orders-app delete pod "$name" --ignore-not-found --wait >/dev/null
  # shellcheck disable=SC2016 # expanded inside the pod, not here
  kubectl -n orders-app run "$name" --restart=Never --image="$PG_IMAGE" \
    --env="PGPASSWORD=$pw" --env="PGCONNECT_TIMEOUT=3" \
    --env="RW=host=$PG_CLUSTER-pooler-rw.$NS.svc dbname=orders user=orders" \
    --env="TABLE=$table" --env="DURATION=$duration" \
    --command -- bash -c '
      end=$(( $(date +%s) + DURATION )); i=0
      while (( $(date +%s) < end )); do
        i=$((i + 1))
        if psql -qtAX "$RW" -c "set statement_timeout = 5000; insert into $TABLE (id) values ($i)" >/dev/null 2>&1; then
          echo "$(date +%s.%N) ok $i"
        else
          echo "$(date +%s.%N) fail $i"
        fi
        sleep 0.1
      done' >/dev/null
  kubectl -n orders-app wait "pod/$name" --for=condition=Ready --timeout=2m >/dev/null
}

# Waits for the writer to finish and saves its log.
# usage: finish_writer <pod-name> <duration-seconds> <logfile>
finish_writer() {
  local name=$1 duration=$2 out=$3
  kubectl -n orders-app wait "pod/$name" --for=jsonpath='{.status.phase}'=Succeeded --timeout=$((duration + 120))s >/dev/null
  kubectl -n orders-app logs "$name" > "$out"
  kubectl -n orders-app delete pod "$name" --wait=false >/dev/null
}

# Waits until the cluster reports a primary other than <old>, then prints the
# operator's promotion time as epoch seconds.
wait_promotion() {
  local old=$1
  until [[ $(kubectl -n "$NS" get "cluster/$PG_CLUSTER" -o jsonpath='{.status.currentPrimary}') != "$old" ]]; do
    sleep 0.5
  done
  kubectl -n "$NS" get "cluster/$PG_CLUSTER" -o jsonpath='{.status.currentPrimaryTimestamp}' |
    python3 -c 'import sys, datetime; print(datetime.datetime.fromisoformat(sys.stdin.read().strip().replace("Z", "+00:00")).timestamp())'
}

# Prints acknowledged/failed writes, the write outage and its timeline, and
# sets GAP (seconds) and LOST (acknowledged writes missing from <table>).
# usage: writer_report <logfile> <table> <t_event> <t_promoted>
writer_report() {
  local logf=$1 table=$2 t_event=$3 t_promoted=$4 ok failed gap_start gap_end
  ok=$(grep -c ' ok ' "$logf" || true)
  failed=$(grep -c ' fail ' "$logf" || true)
  # The outage is the longest gap between two acknowledged writes.
  read -r gap_start gap_end < <(awk '$2 == "ok" {
      if (prev && $1 - prev > max) { max = $1 - prev; s = prev; e = $1 }
      prev = $1 } END { print s, e }' "$logf")
  GAP=$(awk -v s="$gap_start" -v e="$gap_end" 'BEGIN { printf "%.1f", e - s }')
  awk '$2 == "ok" { print $3 }' "$logf" | sort -n > "$logf.acked"
  psql_primary -c "select id from $table order by id" | sort -n > "$logf.stored"
  LOST=$(comm -23 "$logf.acked" "$logf.stored" | wc -l | tr -d ' ')
  echo "writes:   $ok acknowledged, $failed failed"
  echo "downtime: ${GAP}s (longest gap between acknowledged writes)"
  # Relative to the event: when writes stopped, when the operator promoted,
  # when writes resumed. Promotion -> resumed is PgBouncer and the client.
  awk -v k="$t_event" -v s="$gap_start" -v p="$t_promoted" -v e="$gap_end" 'BEGIN {
    printf "timeline: writes stopped at +%.1fs, promotion at +%.1fs, writes resumed at +%.1fs\n", s - k, p - k, e - k }'
  echo "lost:     $LOST acknowledged writes missing"
}
