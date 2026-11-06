# 0002: Three zones, quorum commit, preferred durability

**Status:** accepted

## Decision

- **Three instances, required anti-affinity on the zone.** One primary and
  two standbys, never two in the same zone.
- **Quorum synchronous replication, `ANY 1`.** A commit returns once one of
  the two standbys has flushed it. Losing the primary therefore loses no
  acknowledged transaction; the failover test checks exactly this.
- **`dataDurability: preferred`.** If both standbys are gone the operator
  drops the synchronous requirement and the primary keeps accepting
  writes.

## Why not the alternatives

- **Asynchronous replication:** a failover can lose the last few hundred
  milliseconds of acknowledged writes. Fine for some workloads, not for
  orders and payments.
- **`ANY 2` or `FIRST 1`:** `ANY 2` waits for the slowest standby on every
  commit; `FIRST 1` stalls whenever that one named standby is slow or
  restarting. `ANY 1` of two tolerates one slow or missing standby with no
  latency penalty.
- **`dataDurability: required`:** with both standbys down, writes block
  until one returns. That double failure is rare, and for this workload
  staying writable (with an alert) is the better trade. A ledger-type
  database would choose `required`.
- **Preferred anti-affinity:** after a zone loss the third instance would be
  rescheduled into a surviving zone, so a second zone loss could take out
  two instances at once. With `required` it stays Pending, the cluster
  runs on two instances, and `PostgresStandbyMissing` fires.

## Consequences

- Commit latency includes one cross-zone round trip (typically 1-2 ms in
  Azure and AWS regions).
- A zone outage leaves the cluster at two instances until the zone returns;
  capacity planning assumes that.
