# Infrastructure & DB Initialization Plan — 007-prepare-bicep-and-db-init

## Status

**provision: false** — this task only generates and locally validates Bicep
templates and a separate DB schema-initialization artifact. No Azure resource
was created, modified, or deleted, and no database schema change or data
migration was performed.

## Scope

- Generate `infra/main.bicep` + `infra/modules/*.bicep` (Linux Azure Container
  Apps for `web` and `worker` as separate workloads, PostgreSQL Flexible
  Server, Service Bus, private Blob Storage, per-workload user-assigned
  managed identities with least-privilege ARM role assignments).
- Keep database-level principal grants (PostgreSQL) distinct from ARM roles.
- Enforce TLS everywhere (PostgreSQL `sslmode=require`; Service Bus AMQP/TLS
  only; Storage `minimumTlsVersion=TLS1_2` + HTTPS-only).
- Avoid localhost assumptions in all generated outputs/configuration — every
  connection endpoint is parameterized/derived from deployed resource names
  (`POSTGRESQL_SERVER`, `SERVICE_BUS_NAMESPACE`, `AZURE_STORAGE_BLOB_ENDPOINT`),
  matching the externalized placeholders already present in
  `web`/`worker src/main/resources/application.properties` from tasks
  003–006.
- Prepare `infra/database/init.sql` (schema creation + least-privilege DB
  grants only, no data migration) with a separate execution procedure
  (`infra/database/README.md`), not executed here.
- Validate templates locally only (`az bicep build`); no `az deployment group
  create`/`what-if` or `azd provision` was run.

## Assessment issues addressed (per target configuration)

| Issue | How addressed |
|---|---|
| Local JDBC Calls | PostgreSQL Flexible Server Bicep module targets `*.postgres.database.azure.com` over TLS, Microsoft Entra-only auth (no password at all); no `localhost`/local DB reference anywhere in the generated infrastructure or its outputs. |
| Localhost Usage | All Container App environment variables are sourced from deployed Azure resource outputs (Service Bus namespace, Storage blob endpoint, PostgreSQL server name); no `localhost`/127.0.0.1 default appears in `main.bicep`, its modules, or `main.parameters.json`. |

## Files created

```
infra/
├── main.bicep
├── main.parameters.json
├── modules/
│   ├── identity.bicep
│   ├── containerregistry.bicep
│   ├── loganalytics.bicep
│   ├── containerappenv.bicep
│   ├── containerapp.bicep
│   ├── postgresql.bicep
│   ├── servicebus.bicep
│   └── storage.bicep
├── deploy.sh
├── deploy.ps1
├── README.md
├── compliance.md
└── database/
    ├── init.sql
    └── README.md

.github/modernize/modernization-plan/007-prepare-bicep-and-db-init/
└── plan.md   (this file)
```

`infra-config.md` was intentionally **not** generated: per the infrastructure
skill, it must only be written after a real deployment populates actual
resource values, and this task does not provision anything.

## Execution steps (what was actually done)

1. Read the plan's Infrastructure section and prior task summaries
   (003–006) to confirm the exact environment-variable names the
   application already expects (`SERVICE_BUS_NAMESPACE`,
   `AZURE_MANAGED_IDENTITY_CLIENT_ID`, `AZURE_STORAGE_BLOB_ENDPOINT`,
   `AZURE_STORAGE_CONTAINER_NAME`, `POSTGRESQL_SERVER`,
   `POSTGRESQL_DATABASE`, `POSTGRESQL_USERNAME`) and wired the Bicep outputs
   to match exactly — no new/renamed environment variables were introduced.
2. Called `appmod-get-available-region-sku` for Container Apps, PostgreSQL
   Flexible Server, Service Bus, Storage, Container Registry, and Managed
   Identity; selected `centralus` (confirmed quota for all resource types;
   `eastus2`, used by the legacy `scripts/deploy-to-azure.*`, was not in the
   available-region list).
3. Called `appmod-get-iac-rules` (`deploymentTool=azcli`, `iacType=bicep`) for
   `containerapp`, `azuredatabaseforpostgresql`, `azurecontainerregistry`,
   `azurestorageaccount`, `azurekeyvault` and applied every rule — see
   `infra/compliance.md` for the line-by-line report.
4. Generated `infra/main.bicep` and eight supporting modules under
   `infra/modules/`.
5. Validated every Bicep file with `az bicep build` (main template + each
   module individually) — zero errors, zero warnings. Compiled JSON output
   was deleted after validation (not committed).
6. Generated `infra/database/init.sql` (schema + least-privilege grants only,
   idempotent, placeholders for the two managed-identity names) and
   `infra/database/README.md` documenting the separate, manual execution
   procedure (operator login, `pgaadauth_create_principal`, TLS-only
   `psql`/`az postgres flexible-server execute` connection, grant
   verification).
7. Generated `infra/deploy.sh` / `infra/deploy.ps1` for later, separately
   approved provisioning (not executed by this task).
8. Did **not** run `az deployment group create`, `az deployment group
   what-if`, `azd provision`, or `psql`/`az postgres flexible-server execute`
   against `init.sql`. No Azure resource exists as a result of this task.

## Next steps for the participant (separate approvals required, not part of this task)

1. `azd auth login` / `az login`, choose a resource group and region (one of
   `centralus`, `swedencentral`, `southeastasia`, `westus3`,
   `westcentralus`).
2. Review `infra/main.bicep`, `infra/README.md`, and `infra/compliance.md`;
   once approved, run `infra/deploy.sh` or `infra/deploy.ps1`.
3. Separately review and approve, then manually execute
   `infra/database/init.sql` per `infra/database/README.md`. No existing
   PostgreSQL data or S3 objects are migrated by this step.
4. Build and tag `web`/`worker` container images locally (separate
   containerization task), push to the deployed registry, and
   `az containerapp update --image ...` to replace the placeholder image.
5. Separately approve and run `az containerapp deploy`/image publish steps.
