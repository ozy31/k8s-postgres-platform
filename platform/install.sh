#!/usr/bin/env bash
# Installs the platform layer: cert-manager, the CloudNativePG operator and
# the Barman Cloud plugin. Idempotent; safe to run again after a version bump.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=versions.env
source versions.env

helm_install() {
  local release=$1 chart=$2 version=$3 namespace=$4 values=$5
  helm upgrade --install "$release" "$chart" \
    --version "$version" \
    --namespace "$namespace" --create-namespace \
    --values "$values" \
    --wait --timeout 5m
}

helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update >/dev/null

helm_install cert-manager jetstack/cert-manager "$CERT_MANAGER_CHART_VERSION" \
  cert-manager platform/values/cert-manager.yaml

helm_install cnpg cnpg/cloudnative-pg "$CNPG_CHART_VERSION" \
  cnpg-system platform/values/cloudnative-pg.yaml

# The plugin must live in the operator's namespace; it talks to the operator
# over mTLS using certificates issued by cert-manager.
helm_install barman-cloud cnpg/plugin-barman-cloud "$BARMAN_CLOUD_CHART_VERSION" \
  cnpg-system platform/values/plugin-barman-cloud.yaml

kubectl -n cnpg-system rollout status deployment --timeout=3m
echo "platform ready"
