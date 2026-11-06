# k8s-postgres-platform

[![ci](https://github.com/ozy31/k8s-postgres-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/ozy31/k8s-postgres-platform/actions/workflows/ci.yml)

PostgreSQL as a self-service platform on Kubernetes with
[CloudNativePG](https://cloudnative-pg.io): highly available clusters spread
across three zones, PgBouncer pooling, continuous backup with point-in-time
recovery, Prometheus alerts, and runbooks. Everything runs on a local
three-zone [kind](https://kind.sigs.k8s.io) cluster, and CI does the same, so
failover and restore are tested for real rather than rendered.

## Quick start

```bash
make up      # kind cluster (3 zones) + cert-manager + CNPG operator + Barman Cloud plugin
make down    # delete it
```

Requires Docker, kind, kubectl and helm. Versions are pinned in
[`versions.env`](versions.env).

| Component | Version |
|---|---|
| Kubernetes (kind node) | 1.37.0 |
| CloudNativePG operator | 1.30.1 |
| Barman Cloud plugin | 0.15.1 |
| cert-manager | 1.21.3 |
