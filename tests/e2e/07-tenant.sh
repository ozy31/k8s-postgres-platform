#!/usr/bin/env bash
# A second team onboards from one values file, and the two teams cannot
# reach each other's databases.
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/../.."

log "onboard payments from tenants/payments.yaml"
hack/tenant.sh payments

log "backups and WAL archiving work for the new tenant"
kubectl -n payments wait cluster/payments-db --for=condition=ContinuousArchiving --timeout=5m
kubectl -n payments wait backup -l cnpg.io/scheduled-backup=payments-db-nightly \
  --for=jsonpath='{.status.phase}'=completed --timeout=10m

pay_pw=$(kubectl -n payments get secret payments-db-app -o jsonpath='{.data.password}' | base64 -d)
pay_rw="host=payments-db-pooler-rw.payments.svc dbname=payments user=payments"
client_namespace payments-app payments
client_namespace orders-app orders

log "payments-app reaches payments-db through its pooler"
out=$(client payments-app "$pay_pw" psql -qtAX "$pay_rw" -c "select current_database(), pg_is_in_recovery()")
[[ $out == "payments|f" ]] || fail "payments pooler: $out"

log "orders-app cannot reach payments-db"
if client orders-app "$pay_pw" psql -qtAX "$pay_rw" -c "select 1" 2>/dev/null; then
  fail "orders-app reached the payments pooler"
fi

log "payments-app cannot reach orders-db"
ord_pw=$(secret_value "$PG_CLUSTER-app" password)
if client payments-app "$ord_pw" psql -qtAX "host=$PG_CLUSTER-pooler-rw.$NS.svc dbname=orders user=orders" -c "select 1" 2>/dev/null; then
  fail "payments-app reached the orders pooler"
fi

echo "PASS 07-tenant"
