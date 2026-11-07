# Tenants

One values file per team database, rendered by
[`charts/postgres-cluster`](../charts/postgres-cluster). The chart's
`values.schema.json` rejects bad names, sizes and backup settings before
anything reaches the cluster.

```bash
make tenant TENANT=payments     # namespace, secrets, helm install, wait for Ready
```

Production values differ only in sizing and the backup block:

```yaml
backup:
  provider: azure                       # or s3
  retention: 14d
  destinationPath: https://stpgbackupsprod.blob.core.windows.net/payments-db/
  azureClientId: 11111111-2222-3333-4444-555555555555
storage:
  storageClass: managed-csi-premium
```
