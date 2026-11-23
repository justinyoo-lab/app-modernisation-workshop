# Infrastructure: assets-manager (web + worker) on Azure

This folder contains Bicep templates to provision the Azure infrastructure for
the modernized `assets-manager` application (Java 25 / Spring Boot 4.1.2,
`web` and `worker` modules), per modernization task
`007-prepare-bicep-and-db-init`.

> **This task does not provision any resources.** `provision=false` for this
> task; templates were validated locally only (`az bicep build`). Deployment
> is a separate, manually-approved step performed by the participant/operator
> using `deploy.sh` / `deploy.ps1` below.

## Resources provisioned by `main.bicep`

| Resource | Bicep module | Purpose |
|---|---|---|
| 2× User-Assigned Managed Identity | `modules/identity.bicep` | One per workload (`web`, `worker`); used for ACR pull and all Azure service authentication (PostgreSQL, Service Bus, Blob Storage). No secrets/keys are ever generated for these identities. |
| Azure Container Registry (Basic) | `modules/containerregistry.bicep` | Hosts web/worker container images. `AcrPull` role assigned to each workload identity (admin user disabled). |
| Log Analytics workspace | `modules/loganalytics.bicep` | Backs the Container Apps environment's log destination. |
| Container Apps (managed) Environment | `modules/containerappenv.bicep` | Shared environment for the web and worker Container Apps, wired to Log Analytics. |
| Container App: web | `modules/containerapp.bicep` | Linux Container App, external HTTPS ingress (CORS enabled), pulls images via its own managed identity. Starts from the mandatory placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`; the real image is published and swapped in by a separate, out-of-scope deploy step. |
| Container App: worker | `modules/containerapp.bicep` | Linux Container App, **no ingress** (background Service Bus consumer only), same placeholder-image/identity pattern as web. |
| PostgreSQL Flexible Server (v17) | `modules/postgresql.bicep` | Microsoft Entra-only authentication (`activeDirectoryAuth=Enabled`, `passwordAuth=Disabled`) — there is no PostgreSQL password at all. Firewall rule allows Azure services (`0.0.0.0`). TLS (`sslmode=require`) is enforced by the application's JDBC URL. |
| Service Bus namespace (Standard) + `image-processing` queue | `modules/servicebus.bicep` | `disableLocalAuth=true` (no SAS connection strings). Least-privilege Data Sender/Receiver roles scoped to the single queue. |
| Storage Account (private) + `assets` blob container | `modules/storage.bicep` | `allowSharedKeyAccess=false`, `allowBlobPublicAccess=false`, container `publicAccess=None`. Least-privilege `Storage Blob Data Contributor` scoped to the single container. |

Key Vault was **not** provisioned: every Azure service connection in this
application (PostgreSQL, Service Bus, Blob Storage) uses passwordless Azure
Managed Identity authentication (see `web`/`worker`
`src/main/resources/application.properties`, tasks 003–006), so there are no
application secrets to store. Per the IaC rules, Key Vault should only be
introduced when the application actually has secrets.

## Database principal grants vs. ARM roles (kept distinct)

- **ARM/control-plane roles** (who can manage the Azure *resources*): AcrPull,
  Service Bus Data Sender/Receiver, Storage Blob Data Contributor — all
  defined as `Microsoft.Authorization/roleAssignments` in the Bicep modules
  above, scoped to the narrowest possible resource (queue/container, not
  namespace/account).
- **Database-level principal grants** (who can read/write rows inside
  PostgreSQL): defined separately in `infra/database/init.sql`, run manually
  by a distinct **database operator** identity (the server's Microsoft Entra
  admin, `dbOperatorPrincipalName`/`dbOperatorObjectId` parameters), never by
  this Bicep template and never by the workload managed identities themselves.

These two authorization planes never overlap: an ARM role never grants SQL
privileges, and a SQL `GRANT` never grants ARM/control-plane access.

## Parameters (`main.parameters.json`)

| Parameter | Description |
|---|---|
| `environmentName` | Short name used to derive the `uniqueString` resource token for all resource names. |
| `location` | One of `centralus`, `swedencentral`, `southeastasia`, `westus3`, `westcentralus` — the regions with confirmed `Microsoft.DBforPostgreSQL/flexibleServers` quota at template-authoring time (checked via `appmod-get-available-region-sku`; `eastus2`, used by the legacy `scripts/deploy-to-azure.*` script, did **not** have confirmed PostgreSQL Flexible Server quota and was intentionally not reused). |
| `dbOperatorPrincipalName` / `dbOperatorObjectId` / `dbOperatorPrincipalType` | Identifies the one-time database operator who will later run `infra/database/init.sql`. Must be a human/group/service-principal distinct from the `web`/`worker` workload managed identities. |

No password, connection-string, or other secret parameter exists anywhere in
this template.

## Outputs

`main.bicep` emits only non-secret values: registry login server, Container
Apps environment/app names and FQDNs, workload managed identity names/client
IDs, PostgreSQL server name/FQDN/database name, Service Bus namespace/queue
name, and storage account name/blob endpoint/container name. These are the
same values referenced as placeholders (`${POSTGRESQL_SERVER}`,
`${SERVICE_BUS_NAMESPACE}`, `${AZURE_STORAGE_BLOB_ENDPOINT}`, etc.) in
`web`/`worker` `application.properties`, and are wired automatically as
Container App environment variables in `modules/containerapp.bicep`.

## Validation performed (local only — no resources were created)

```
az bicep build --file infra/main.bicep
```

completed with no errors or warnings. No `az deployment group create`,
`az deployment group what-if` (which requires a live resource group), or
`azd provision` command was executed as part of this task.

## Deploying later (separate, approved step — not part of this task)

```bash
./infra/deploy.sh -g <resourceGroupName> -l centralus -e <environmentName> \
    -o <dbOperatorPrincipalName> -i <dbOperatorObjectId>
```

```powershell
./infra/deploy.ps1 -ResourceGroupName <resourceGroupName> -Location centralus `
    -EnvironmentName <environmentName> -DbOperatorPrincipalName <name> -DbOperatorObjectId <guid>
```

Both scripts run `az bicep build` and `az deployment group what-if` first and
prompt for confirmation before `az deployment group create`. Neither script
runs `infra/database/init.sql` — see `infra/database/README.md` for that
separate, manually-approved procedure.

## Compliance

See `compliance.md` for a line-by-line mapping of applied IaC rules.
