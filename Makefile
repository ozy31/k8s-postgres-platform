SHELL := /usr/bin/env bash
include versions.env
export

CLUSTER ?= pg-platform

.PHONY: help cluster platform up db test down lint alerts monitoring validate tenant chart

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

cluster: ## Create the kind cluster (three zones)
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/cluster.yaml --image $(KIND_NODE_IMAGE) --wait 2m

platform: ## Install cert-manager, the CNPG operator, the Barman Cloud plugin and local S3
	platform/install.sh
	platform/object-store/install.sh

db: ## Deploy the orders-db Postgres cluster (local overlay)
	kubectl apply -k postgres/overlays/local
	hack/ensure-secret.sh orders orders-db-readonly orders_readonly
	kubectl -n orders wait cluster/orders-db --for=condition=Ready --timeout=10m

up: cluster platform db ## Cluster, platform and database

test: ## Run the end-to-end tests against the running cluster
	@for t in tests/e2e/[0-9]*.sh; do $$t || exit 1; done

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

validate: chart ## Server-side dry run of every overlay and tenant against the live CRDs
	@for o in postgres/overlays/*/; do \
	  echo "== $$o"; \
	  kubectl kustomize $$o | kubectl apply --dry-run=server -f - >/dev/null || exit 1; \
	done
	@for t in tenants/*.yaml; do \
	  echo "== $$t"; \
	  helm template x charts/postgres-cluster -n orders -f $$t | kubectl apply -n orders --dry-run=server -f - >/dev/null || exit 1; \
	done

chart: ## Lint the tenant chart; its alerts must match postgres/base
	helm lint charts/postgres-cluster -f tenants/payments.yaml
	@diff <(yq '.spec' postgres/base/prometheusrule.yaml) charts/postgres-cluster/files/alerts.yaml \
	  || { echo "charts/postgres-cluster/files/alerts.yaml is out of date: yq '.spec' postgres/base/prometheusrule.yaml > charts/postgres-cluster/files/alerts.yaml"; exit 1; }

tenant: ## Onboard tenants/$(TENANT).yaml with the chart
	hack/tenant.sh $(TENANT)

alerts: ## Check and unit-test the alert rules with promtool
	yq '.spec' postgres/base/prometheusrule.yaml > tests/alerts/rules.generated.yaml
	promtool check rules tests/alerts/rules.generated.yaml
	promtool test rules tests/alerts/postgres.test.yaml

monitoring: ## Optional: Prometheus + Grafana with the CNPG dashboard (not in CI)
	monitoring/install.sh

lint: ## yamllint and shellcheck
	yamllint -s .
	shellcheck -x $$(find . -name '*.sh' -not -path './.git/*')
