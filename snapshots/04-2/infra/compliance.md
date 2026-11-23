# IaC Rule Compliance Report — `infra/main.bicep`

Generated for modernization task `007-prepare-bicep-and-db-init`
(`provision=false`; templates validated locally only via `az bicep build`).

## General rules

| Rule | Applied? | Evidence |
|---|---|---|
| Call `appmod-get-available-region-sku` before choosing region/SKU | ✅ | Queried for Container Apps, PostgreSQL Flexible Server, Service Bus, Storage, Container Registry, Managed Identity. `centralus` selected (192 core quota remaining for PostgreSQL; `eastus2` was not in the available-region list). |
| If current region unavailable, choose an available region + add naming index | ✅ (N/A conflict) | `centralus` chosen directly; `location` param restricted via `@allowed` to the five confirmed-available regions so a future redeploy can't silently target an unchecked region. |
| Resource token format `uniqueString(subscription().id, resourceGroup().id, location, environmentName)` (resourceGroup scope) | ✅ | `main.bicep`: `var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)`. |
| Resource names `az{resourcePrefix<=3 chars}{resourceToken}`, alphanumeric only | ✅ | `idw`/`ido` (web/worker identity), `acr`, `log`, `cae`, `caw`/`cao` (web/worker container app), `pg`, `sb`, `st` (storage, further `take()`-truncated to 24 chars for the storage-account length limit). |
| Expected files: `main.bicep`, `main.parameters.json` | ✅ | Both present at `infra/`. |

## Container Apps

| Rule | Applied? | Evidence |
|---|---|---|
| Attach User-Assigned Managed Identity | ✅ | `modules/containerapp.bicep`: `identity.type = 'UserAssigned'`, one identity per app (web/worker), not shared. |
| Add `AcrPull` role assignment to the identity (one instance per registry, defined before any container apps) | ✅ | `modules/containerregistry.bicep`: loop over both identities' principal IDs, defined in the `containerRegistry` module which is deployed independently of (and referenced by) the container app modules. |
| Use this identity (not system) to connect to the registry; registry connection required even with a template base image | ✅ | `configuration.registries[0].identity = identityResourceId` (user-assigned resource ID, not `'system'`). |
| Base image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` via `properties.template.containers.image` | ✅ | `modules/containerapp.bicep`: `placeholderImage` constant used for both apps; real app image is an explicitly out-of-scope, separate deploy step. |
| Use `properties.configuration.registries` for the registry connection | ✅ | As above. |
| Enable CORS via `properties.configuration.ingress.corsPolicy` | ✅ | Applied to the `web` app's ingress (the only app with ingress). |
| Define all used secrets; use Key Vault if possible | ✅ (N/A) | No secrets are used anywhere (fully passwordless/managed-identity auth for PostgreSQL, Service Bus, Blob Storage); Key Vault intentionally omitted per the Key Vault rule below. No `configuration.secrets` block is needed. |
| Add Key Vault secrets + role assignment as explicit dependencies | ✅ (N/A) | No Key Vault / secrets exist in this template. |
| Container Apps environment connected to Log Analytics via `logAnalyticsConfiguration` (`customerId`, `sharedKey` from `listKeys()`) | ✅ | `modules/containerappenv.bicep`: `logAnalyticsConfiguration.customerId`/`sharedKey` populated from `modules/loganalytics.bicep` outputs (`sharedKey` output marked `@secure()`). |

## PostgreSQL

| Rule | Applied? | Evidence |
|---|---|---|
| Version `17` or higher | ✅ | `postgresVersion` default `'17'`. |
| Don't name the database `postgres` | ✅ | Database name is `assets_manager`. |
| Firewall rule to allow Azure services (`0.0.0.0`) | ✅ | `modules/postgresql.bicep`: `AllowAllAzureServicesAndResourcesWithinAzureIps` firewall rule, `0.0.0.0`–`0.0.0.0`. |
| If app uses username/password → leave as params + store in Key Vault | ✅ (N/A) | App uses Managed Identity only; `authConfig.passwordAuth = 'Disabled'` — no password exists to store. |
| If app uses Managed Identity → MUST add post-provision Service Connector step | ⚠️ Documented, not executed | This task's scope is template preparation and local validation only (`provision=false`); no resource exists yet to connect. `infra/database/README.md` and `infra/database/init.sql` document the equivalent (and more auditable) manual `pgaadauth_create_principal` + least-privilege `GRANT` procedure, run by a distinct DB operator identity, instead of the Service Connector CLI flow — matching the task's explicit requirement to keep DB initialization in "a separate, reviewable procedure" that is not run automatically. The connection details (`POSTGRESQL_SERVER`, `POSTGRESQL_DATABASE`, `POSTGRESQL_USERNAME`) are still wired as Container App environment variables exactly as Service Connector would set them. |

## Container Registry

No additional rules beyond the Container Apps section above (AcrPull, admin user disabled).

## Storage Accounts

| Rule | Applied? | Evidence |
|---|---|---|
| Disable local auth (key access) by default | ✅ | `modules/storage.bicep`: `allowSharedKeyAccess: false`. |
| Disable anonymous blob access by default | ✅ | `allowBlobPublicAccess: false`; container `publicAccess: 'None'`. |

## Key Vault

Not applicable — no Key Vault resource was created, because the application
has no secrets to store (see Container Apps "secrets" row above). This itself
follows the stated rule: "Use Key Vault only when application has secrets to
store."

## Deviations / notes

- `az deployment group what-if` and `az deployment group create` were **not**
  executed as part of this task (no resource group target exists yet, and the
  task explicitly forbids provisioning). Validation was limited to
  `az bicep build`, which compiled with zero errors/warnings.
- The legacy `scripts/deploy-to-azure.sh/.cmd` admin-login-based PostgreSQL
  provisioning approach (`--active-directory-auth Enabled` but still allowing
  password auth, per that script) was **not** reused; this Bicep deployment
  instead disables password auth entirely (`passwordAuth: 'Disabled'`), which
  is a stricter, Entra-only posture consistent with the "DB principal grants
  distinct from ARM roles" requirement.
