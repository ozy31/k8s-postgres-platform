# External Secrets

In the cloud, database role passwords live in Azure Key Vault or AWS Secrets
Manager and reach the cluster through
[External Secrets](https://external-secrets.io). Each environment has one
`ClusterSecretStore` named `platform-secrets`, so the database overlays
(`postgres/overlays/aks`, `eks`) are identical in how they ask for a secret.

| File | Store | Credentials |
|---|---|---|
| `azure-key-vault.yaml` | Key Vault | workload identity |
| `aws-secrets-manager.yaml` | Secrets Manager | EKS Pod Identity |

Rotation: change the value in the vault. The `ExternalSecret` refreshes
hourly, and the target Secret carries `cnpg.io/reload: "true"`, so the
operator applies the new password to the role without a restart.

Locally there is no vault; `hack/ensure-secret.sh` generates the same Secret.
CI installs only the External Secrets CRDs, to validate these files and the
overlays with a server-side dry run.
