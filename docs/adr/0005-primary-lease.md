# 0005: Primary lease of 10 seconds

**Status:** accepted

## Context

The first CI run showed 41.5 s of write downtime on failover and the laptop
showed 22 s, against a promotion that should take a couple of seconds. The
failover test now prints a timeline. The operator log and the new primary's
log for one run with the defaults:

| Time | Event |
|---|---|
| +0 s | primary pod force-deleted |
| +2 s | last acknowledged write; the operator decides to fail over |
| +3 s | operator sets `targetPrimary` |
| **+19 s** | standby logs "I'm the target primary", promotes |
| +21 s | primary label moved; service endpoints follow |
| +22 s | first acknowledged write through the pooler |

The 16 s of waiting is the **primary lease** (CNPG 1.30): a Kubernetes
`Lease` held by the primary. A primary that shuts down cleanly releases it
with a 1 s TTL, which is why a switchover takes about 4 s to promote. A
primary that crashed cannot release it, so the standby waits for the full
`leaseDurationSeconds` (15 s by default) before promoting. That wait is the
guard against two primaries at once.

## Measurements

Same test, same kind cluster, one run each:

| `leaseDuration / renewDeadline / retryPeriod` | Promotion | Write downtime |
|---|---|---|
| 15 / 10 / 2 (default) | +21.5 s | 22.2 s |
| **10 / 6 / 2** | **+14.9 s** | **16.1 s** |
| 6 / 4 / 1 | +11.0 s | 11.0 s |

## Decision

10 / 6 / 2 in the base.

The other side of the lease is `renewDeadlineSeconds`: a primary that
cannot renew its lease for that long **stops itself**, because it can no
longer prove it is still the primary. Shorter values mean faster failover
and also that a short API server outage takes the primary down:

- 6 / 4 / 1 would stop the primary after 4 s without the API server. AKS and
  EKS control plane upgrades and API server restarts can exceed that, and
  every such blip would become a database outage.
- 10 / 6 / 2 saves about 6 s per failover and still tolerates a 6 s API
  server outage.

## Consequences

- Unplanned failover: about 16 s of write downtime on kind. Planned
  switchover is unaffected (about 10 s, tests/e2e/05-switchover.sh).
- If the platform runs on a control plane with a higher SLA or a private
  control plane in the same zone, revisit with the test, not by guessing.
- Clients still need retry logic: 16 s is short for an outage, long for a
  synchronous request.
