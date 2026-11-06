#!/usr/bin/env bash
# Optional local Prometheus, Alertmanager and Grafana. Not part of CI: the
# alert rules are unit-tested with promtool instead (make alerts).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
source versions.env

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 18 | tr -d '/+=')"
fi

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --version "$KUBE_PROMETHEUS_STACK_CHART_VERSION" \
  --namespace monitoring \
  --values monitoring/values.yaml \
  --wait --timeout 10m

cat <<MSG
Grafana:    kubectl -n monitoring port-forward svc/kps-grafana 3000:80
            user admin, password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
Prometheus: kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090
MSG
