# Connections, pool waits, long transactions

## Near max_connections

Applications should not be able to reach Postgres directly (ADR 0003), so
high backend counts mean the pools are too big or something bypasses them.

```bash
kubectl cnpg psql orders-db -n orders -- -c "
  select usename, application_name, client_addr, state, count(*)
  from pg_stat_activity where backend_type = 'client backend'
  group by 1, 2, 3, 4 order by 5 desc"
```

Server connections from poolers = pooler pods x (`default_pool_size` +
`reserve_pool_size`). Keep that well below `max_connections`.

## PgBouncer clients waiting

Clients are queued for a server connection. Either the database is slow
(look at `pg_stat_statements` and locks first) or the pool is genuinely too
small. Raise `default_pool_size` only after ruling out the first.

```bash
kubectl cnpg psql orders-db -n orders -- -c "
  select calls, round(mean_exec_time::numeric, 1) as mean_ms, query
  from pg_stat_statements order by total_exec_time desc limit 10"
```

## Long transaction

```bash
kubectl cnpg psql orders-db -n orders -- -c "
  select pid, usename, now() - xact_start as age, state, left(query, 80)
  from pg_stat_activity where xact_start is not null order by xact_start limit 10"
```

`idle in transaction` sessions are closed after 10 minutes
(`idle_in_transaction_session_timeout`). For an active one, ask the owner,
then `select pg_cancel_backend(<pid>)`, and `pg_terminate_backend` only if
cancel does not work.
