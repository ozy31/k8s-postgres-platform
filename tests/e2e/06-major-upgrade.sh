#!/usr/bin/env bash
# In-place major upgrade, 17 -> 18, on a throwaway two-instance cluster:
# the procedure from docs/runbooks/major-upgrade.md, timed.
source "$(dirname "$0")/lib.sh"

UPGRADE=upgrade-check
FROM=ghcr.io/cloudnative-pg/postgresql:17.9-minimal-trixie
TO=$PG_IMAGE
cleanup() { kubectl -n "$NS" delete cluster "$UPGRADE" --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

upsql() {
  local pod
  pod=$(kubectl -n "$NS" get pods -l "cnpg.io/cluster=$UPGRADE,cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl -n "$NS" exec "$pod" -c postgres -- psql -qtAX -d app "$@"
}

log "two-instance cluster on PostgreSQL 17"
kubectl -n "$NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $UPGRADE
spec:
  imageName: $FROM
  instances: 2
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      memory: 256Mi
  storage:
    size: 1Gi
YAML
kubectl -n "$NS" wait "cluster/$UPGRADE" --for=condition=Ready --timeout=10m
upsql -c "create table upgrade_check as select g as id, md5(g::text) as v from generate_series(1, 10000) g"
before=$(upsql -c "select md5(string_agg(v, '' order by id)) from upgrade_check")
upsql -c "select version()"

log "switch the image to PostgreSQL 18"
start=$(date +%s)
kubectl -n "$NS" patch cluster "$UPGRADE" --type merge -p "{\"spec\":{\"imageName\":\"$TO\"}}"

# The operator shuts the cluster down, runs pg_upgrade in a job, then
# recreates the standby; wait until it reports the new major and is Ready.
until [[ $(kubectl -n "$NS" get cluster "$UPGRADE" -o jsonpath='{.status.pgDataImageInfo.majorVersion}') == 18 ]]; do
  (( $(date +%s) - start < 900 )) || fail "no upgrade to 18 after 15 minutes"
  sleep 5
done
kubectl -n "$NS" wait "cluster/$UPGRADE" --for=condition=Ready --timeout=10m
echo "upgrade took $(( $(date +%s) - start ))s (cluster unavailable for most of it)"

log "version, data and replication after the upgrade"
upsql -c "select version()"
[[ $(upsql -c "show server_version_num") == 18* ]] || fail "not on 18"
after=$(upsql -c "select md5(string_agg(v, '' order by id)) from upgrade_check")
[[ $before == "$after" ]] || fail "data changed across the upgrade"
streaming=$(upsql -c "select count(*) from pg_stat_replication where state = 'streaming'")
[[ $streaming == 1 ]] || fail "$streaming streaming standbys after upgrade, want 1"

echo "PASS 06-major-upgrade"
