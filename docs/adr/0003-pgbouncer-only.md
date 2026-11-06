# 0003: PgBouncer as the only way in

**Status:** accepted

## Decision

Applications connect to `orders-db-pooler-rw` / `-ro`, in transaction
pooling mode. NetworkPolicies block direct connections to Postgres from
anything except the poolers, the other instances and the operator.

## Why

- **Connection storms.** Autoscaled services open connections per pod. 200
  pgbench clients run on at most 50 server connections in the e2e test;
  without the pooler each would be a Postgres backend with its own memory.
- **Failover is invisible to clients.** The pooler's Service never changes;
  CNPG repoints PgBouncer to the new primary.
- **Enforced, not recommended.** If direct access were possible, someone
  would use it, and the `max_connections` budget would stop meaning
  anything.

## Consequences

Transaction pooling breaks session state across transactions:

- `SET` outside a transaction, session advisory locks, `LISTEN/NOTIFY`,
  and temporary tables that outlive a transaction do not work. Use
  `SET LOCAL`, transaction-level advisory locks, and a dedicated session
  pooler for the rare consumer that needs `LISTEN`.
- Protocol-level prepared statements work: PgBouncer tracks them
  (`max_prepared_statements: 200` on the rw pooler). `PREPARE` as SQL
  does not.
- Migrations that need session features run as a Job with an explicit
  NetworkPolicy exception, or through `kubectl cnpg psql`.
