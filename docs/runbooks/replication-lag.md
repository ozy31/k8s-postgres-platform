# Replication lag

```bash
kubectl cnpg status orders-db -n orders      # lag per standby
kubectl cnpg psql orders-db -n orders -- -c "select application_name, state, sync_state, write_lag, flush_lag, replay_lag from pg_stat_replication"
```

Quorum commit waits for one standby, so the other can fall behind without
slowing commits. Lag on both is a problem.

| Look at | Cause | Action |
|---|---|---|
| `replay_lag` high, `flush_lag` low | standby is receiving but cannot apply fast enough, or a long query on it is conflicting | check `pg_stat_activity` on the standby; long reporting queries belong on the ro pooler with `statement_timeout` |
| `write_lag`/`flush_lag` high | network or standby disk | node/disk metrics for the standby's zone |
| lag only during bulk loads | WAL volume | batch the job, or schedule it off-peak |

If one standby is persistently unhealthy, rebuild it:
`kubectl cnpg destroy orders-db <instance> -n orders`.
