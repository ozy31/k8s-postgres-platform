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
