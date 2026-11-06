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
make up      # kind cluster (3 zones), platform operators, orders-db
make test    # end-to-end tests against the running cluster
make down    # delete it
```

## The database

`orders-db` ([`postgres/base`](postgres/base)) is what a team gets:

- **Three instances, one per zone.** Required anti-affinity on
  `topology.kubernetes.io/zone`, PodDisruptionBudget on.
- **Quorum commit.** `ANY 1` of the two standbys must confirm each commit,
  so losing the primary loses no acknowledged transaction. With
  `dataDurability: preferred` the primary stays writable if both standbys
  are down.
- **Updates by switchover.** Replicas restart first, then the operator
  switches over to an updated replica, so the primary is never restarted
  in place.
- **Separate WAL volume**, data checksums, slow query and lock logging.
- **Declarative roles and extensions.** A read-only role and
  `pg_stat_statements` are reconciled by the operator (`managed.roles`, the
  `Database` resource). Passwords are generated outside git
  ([`hack/ensure-secret.sh`](hack/ensure-secret.sh)).
- **PgBouncer in front, and only PgBouncer.** Two `Pooler`s (rw and ro),
  two pods each in different zones, transaction pooling. NetworkPolicies
  deny everything else: apps in namespaces labelled `team: orders` reach the
  poolers, and only the poolers, the other instances and the operator reach
  Postgres. The e2e test checks both the allowed and the blocked paths, and
  that 200 pgbench clients run on at most 50 server connections.

Requires Docker, kind, kubectl and helm. Versions are pinned in
[`versions.env`](versions.env).

| Component | Version |
|---|---|
| Kubernetes (kind node) | 1.37.0 |
| CloudNativePG operator | 1.30.1 |
| Barman Cloud plugin | 0.15.1 |
| cert-manager | 1.21.3 |
