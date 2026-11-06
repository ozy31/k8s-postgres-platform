SHELL := /usr/bin/env bash
include versions.env
export

CLUSTER ?= pg-platform

.PHONY: help cluster platform up db test down lint

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

cluster: ## Create the kind cluster (three zones)
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/cluster.yaml --image $(KIND_NODE_IMAGE) --wait 2m

platform: ## Install cert-manager, the CNPG operator and the Barman Cloud plugin
	platform/install.sh

db: ## Deploy the orders-db Postgres cluster (local overlay)
	kubectl apply -k postgres/overlays/local
	hack/ensure-secret.sh orders orders-db-readonly orders_readonly
	kubectl -n orders wait cluster/orders-db --for=condition=Ready --timeout=10m

up: cluster platform db ## Cluster, platform and database

test: ## Run the end-to-end tests against the running cluster
	@for t in tests/e2e/[0-9]*.sh; do $$t || exit 1; done

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

lint: ## yamllint and shellcheck
	yamllint -s .
	shellcheck -x $$(find . -name '*.sh' -not -path './.git/*')
