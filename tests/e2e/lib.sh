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
