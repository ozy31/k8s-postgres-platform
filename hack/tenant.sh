#!/usr/bin/env bash
# Onboards a team database from tenants/<name>.yaml into namespace <name>.
# usage: hack/tenant.sh <name>
set -euo pipefail
cd "$(dirname "$0")/.."

tenant=$1
values=tenants/$tenant.yaml
[[ -f $values ]] || { echo "no $values" >&2; exit 1; }
name=$(yq '.name' "$values")
team=$(yq '.team' "$values")
db=$(yq '.database.name' "$values")

kubectl create namespace "$tenant" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$tenant" team="$team" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null

hack/ensure-secret.sh "$tenant" "$name-readonly" "${db}_readonly"

# Local only: reuse the SeaweedFS key. In the cloud the backup block uses
# workload identity / Pod Identity and no Secret exists.
if [[ $(yq '.backup.provider' "$values") == local ]] &&
  ! kubectl -n "$tenant" get secret local-s3-credentials >/dev/null 2>&1; then
  kubectl -n orders get secret orders-db-backup-s3 -o json |
    jq --arg ns "$tenant" '{apiVersion, kind, type, data, metadata: {name: "local-s3-credentials", namespace: $ns}}' |
    kubectl apply -f - >/dev/null
fi

helm upgrade --install "$name" charts/postgres-cluster -n "$tenant" -f "$values" --wait
kubectl -n "$tenant" wait "cluster/$name" --for=condition=Ready --timeout=10m
