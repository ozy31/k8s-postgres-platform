# 0001: CloudNativePG instead of a managed service or Patroni

**Status:** accepted

## Context

Teams need Postgres with HA, backups and PITR. The options:

1. **Managed service** (Azure Database for PostgreSQL Flexible Server, RDS/Aurora).
2. **Patroni-based operators** (Zalando, Crunchy PGO).
3. **CloudNativePG.**

## Decision

CloudNativePG, for workloads that already run on the Kubernetes platform.

- **No external consensus store.** Patroni needs etcd/Consul or the
  Kubernetes API as a DCS and runs its own leader election next to the
  operator. CNPG's operator and instance manager use the Kubernetes API
  directly, so there is one control loop, not two.
- **Everything is a Kubernetes resource.** Roles, databases, extensions,
  poolers, backups and their schedules are reconciled from git like any
  other workload. A new environment needs no manual SQL.
- **Cost and placement.** Instances run on the cluster's existing nodes with
  local-zone storage, beside the application, with no per-instance service
  premium.
- **Portability.** The same manifests run on AKS, EKS and kind; only the
  object store and storage class differ (see the overlays).

## Consequences

- We own what a managed service would: minor/major upgrades, capacity,
  backup verification, on-call. The runbooks and the e2e tests exist
  because of this.
- Managed services remain the default for databases outside the platform,
  or where a team has no Kubernetes footprint, or needs features like
  cross-region read replicas without building them.
- The operator is now critical infrastructure: it is pinned, upgraded
  deliberately, and its failure does not stop running databases (instances
  keep serving; only reconciliation pauses).
