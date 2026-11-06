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
make up      # kind cluster (3 zones), operators, local S3, orders-db
make test    # end-to-end tests against the running cluster
make alerts  # promtool unit tests for the alert rules
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
- **Continuous backup.** The Barman Cloud plugin archives WAL as it is
  written and takes a base backup every night (and once at creation), with
  7 days' retention. Locally the target is SeaweedFS's S3 API
  ([`platform/object-store`](platform/object-store)); keys are generated at
  install time and never committed.
- **Point-in-time restore, tested.** The e2e test writes 1000 rows, notes the
  time, deletes them, then restores
  [`postgres/restore`](postgres/restore/orders-db-restore.yaml) to that
  moment in a new cluster next to the original and checks the rows are back.
  On kind this takes about a minute.

## AKS and EKS

The same base runs in the cloud; only the overlay changes.

| | local | [aks](postgres/overlays/aks) | [eks](postgres/overlays/eks) |
|---|---|---|---|
| Backup target | SeaweedFS S3 | Azure Blob | S3 |
| Credentials | generated key in a Secret | workload identity (federated managed identity) | EKS Pod Identity |
| Storage class | local-path | `managed-csi-premium` | `gp3` |
| Sizing | 384Mi, 2Gi + 1Gi WAL | 8Gi, 256Gi + 64Gi WAL | 8Gi, 256Gi + 64Gi WAL |
| Retention | 7 days | 14 days | 14 days |

No storage keys, SAS tokens or access keys appear in either cloud overlay.
On AKS the operator-created service account `orders-db` carries the managed
identity's client ID, and the `azure.workload.identity/use` label is
inherited by the pods, so the backup sidecar gets the token too. On EKS a
Pod Identity association for `orders/orders-db` grants the role.

The cloud overlays have not been deployed from this repo. CI does a
server-side dry run of both against the live CNPG and Barman Cloud CRDs on
the kind cluster (`make validate`), so schema mistakes fail the build.

## Monitoring

Each cluster ships its own `PodMonitor`s (Postgres on 9187, PgBouncer on
9127) and a `PrometheusRule` with 12 alerts
([`postgres/base/prometheusrule.yaml`](postgres/base/prometheusrule.yaml)):
instance down, no primary, fewer than two standbys, replication lag, WAL
archiving stuck, base backup too old or failed, connections near
`max_connections`, PgBouncer clients waiting, long transactions, XID age, and
volumes filling up. Every alert links to a runbook.

The rules are unit-tested with `promtool` in CI (`make alerts`,
[`tests/alerts`](tests/alerts/postgres.test.yaml)), including the cases that
must *not* fire, such as a standby's archiver looking idle.

Two details that came from running it rather than reading docs:

- With backups going through the Barman Cloud plugin, the operator's own
  `cnpg_collector_last_available_backup_timestamp` stays at 0. Backup age has
  to come from the plugin's `barman_cloud_cloudnative_pg_io_*` series, or the
  backup alert fires forever (or never).
- kind's local-path volumes publish no `kubelet_volume_stats_*`, so the
  volume alert can only be exercised by the unit test locally. On AKS (Azure
  Disk CSI) and EKS (EBS CSI) the series exist.

`make monitoring` installs kube-prometheus-stack with the CloudNativePG
Grafana dashboard for local use. CI skips it.

## Failover, measured

[`tests/e2e/04-failover.sh`](tests/e2e/04-failover.sh) runs a client that
inserts a row through the rw pooler every 100 ms, force-deletes the primary
pod after 20 s, and then compares what the client saw acknowledged with what
is in the table. A run on the local kind cluster:

```text
primary:  orders-db-1 -> orders-db-2
writes:   474 acknowledged, 23 failed
downtime: 23.6s (longest gap between acknowledged writes)
lost:     0 acknowledged writes missing after failover
```

Zero lost writes is the point of quorum commit: every acknowledged
transaction was already on a standby when the primary disappeared. The
clients needed no change, because the pooler's service follows the new
primary. The test fails if any acknowledged write is missing, if writes are
down for 60 s or more, or if the old primary does not come back as a
streaming replica. The downtime figure is from kind on a laptop; on a cloud
cluster it depends on how fast the node or pod loss is detected.

Requires Docker, kind, kubectl and helm. Versions are pinned in
[`versions.env`](versions.env).

| Component | Version |
|---|---|
| Kubernetes (kind node) | 1.37.0 |
| CloudNativePG operator | 1.30.1 |
| Barman Cloud plugin | 0.15.1 |
| cert-manager | 1.21.3 |
| PostgreSQL | 18.6 |
| SeaweedFS (local S3) | 4.52 |
| Prometheus Operator CRDs | 0.95.1 |

## Design decisions

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-cloudnative-pg.md) | CloudNativePG instead of a managed service or a Patroni-based operator |
| [0002](docs/adr/0002-topology-and-durability.md) | Three zones, `ANY 1` quorum commit, `preferred` durability, required anti-affinity |
| [0003](docs/adr/0003-pgbouncer-only.md) | PgBouncer in transaction mode as the only way in, and what that breaks |
| [0004](docs/adr/0004-backups.md) | Barman Cloud plugin; restore beside the original, never over it |

## Runbooks

[`docs/runbooks`](docs/runbooks): one per alert group, plus point-in-time
restore and major version upgrade procedures.

## Layout

```text
kind/                 three-zone kind cluster
platform/             operators (install.sh) and local S3 (object-store/)
postgres/base/        Cluster, Poolers, Database, NetworkPolicies, backups, monitoring
postgres/overlays/    local (SeaweedFS), aks (Azure Blob), eks (S3)
postgres/restore/     point-in-time restore cluster
monitoring/           optional Prometheus + Grafana for local use
tests/e2e/            cluster, pooler, backup/restore, failover
tests/alerts/         promtool unit tests
docs/                 ADRs and runbooks
```
