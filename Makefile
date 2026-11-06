SHELL := /usr/bin/env bash
include versions.env
export

CLUSTER ?= pg-platform

.PHONY: help cluster platform up down lint

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

cluster: ## Create the kind cluster (three zones)
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/cluster.yaml --image $(KIND_NODE_IMAGE) --wait 2m

platform: ## Install cert-manager, the CNPG operator and the Barman Cloud plugin
	platform/install.sh

up: cluster platform ## Cluster and platform

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

lint: ## yamllint and shellcheck
	yamllint -s .
	shellcheck -x $$(find . -name '*.sh' -not -path './.git/*')
