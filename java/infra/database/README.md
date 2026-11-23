# Database Initialization Procedure (manual, reviewable, NOT executed by the modernization plan)

This folder contains a **separate, reviewable** schema-initialization artifact
(`init.sql`) for the Azure Database for PostgreSQL Flexible Server provisioned
by `infra/main.bicep`. It is intentionally **not run** by the
`007-prepare-bicep-and-db-init` modernization task, any other automated task,
or any script in this repository. A human database operator must review and
execute it manually, after separate approval, per the plan's
"별도 DB 초기화 및 참가자 azd 절차" (separate DB initialization and participant
azd procedure) section.

## What `init.sql` does

- Creates the `image_metadata` table and a supporting index (idempotent —
  `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`).
- Creates two Microsoft Entra-backed, non-administrative PostgreSQL database
  roles — one per workload managed identity (web, worker) — using
  `pgaadauth_create_principal`.
- Grants least-privilege, table-scoped privileges to each role:
  - web: `SELECT, INSERT, UPDATE, DELETE` (matches upload/list/view/delete behavior).
  - worker: `SELECT, UPDATE` only (matches thumbnail-metadata-update behavior).

## What `init.sql` deliberately does NOT do

- **No data migration.** It contains no `INSERT`/`COPY`/data-copy statements.
  Migrating existing PostgreSQL rows, local dev files, or S3 objects is out of
  scope for this task and requires its own separate, explicitly approved task.
- **No ARM/control-plane operations.** It only issues PostgreSQL `CREATE`/
  `GRANT` statements over a `psql` connection; it never calls `az`/ARM APIs
  and never modifies role assignments defined in the Bicep modules.
- **No password-based credentials.** The server is deployed with
  `authConfig.activeDirectoryAuth = Enabled` and `passwordAuth = Disabled`;
  there is no PostgreSQL password to create, store, or rotate.

## Prerequisites

1. `infra/main.bicep` has already been deployed successfully (see
   `infra/README.md` / `infra/deploy.sh` / `infra/deploy.ps1`), and you have
   the Bicep deployment outputs for:
   - `POSTGRESQL_SERVER_FQDN`, `POSTGRESQL_DATABASE_NAME`
   - `WEB_MANAGED_IDENTITY_NAME`, `WORKER_MANAGED_IDENTITY_NAME`
2. You are signed in (`az login`) as the **database operator** principal that
   was passed as `dbOperatorPrincipalName` / `dbOperatorObjectId` when
   deploying `main.bicep` (the server's Microsoft Entra administrator). This
   operator identity is intentionally **separate** from the web/worker
   workload managed identities — never run this script as, or grant these
   roles to, the application's own managed identity.
3. The PostgreSQL client tools (`psql`) are installed locally, or you use
   `az postgres flexible-server execute` (Azure CLI `rdbms-connect`
   extension), either of which connects over TLS by default.

## Execution (run manually — this is NOT automated)

1. Replace the two placeholders in `init.sql`:
   - `<WEB_MANAGED_IDENTITY_NAME>` → the `WEB_MANAGED_IDENTITY_NAME` Bicep output.
   - `<WORKER_MANAGED_IDENTITY_NAME>` → the `WORKER_MANAGED_IDENTITY_NAME` Bicep output.

2. Obtain a Microsoft Entra access token for PostgreSQL as the operator:

   ```bash
   export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
   ```

3. Connect and execute the script over TLS (never disable TLS/`sslmode`):

   ```bash
   psql "host=<POSTGRESQL_SERVER_FQDN> port=5432 dbname=<POSTGRESQL_DATABASE_NAME> \
         user=<dbOperatorPrincipalName> sslmode=require" \
        -f infra/database/init.sql
   ```

   Or, using the Azure CLI extension (no local `psql` required):

   ```bash
   az extension add --name rdbms-connect --upgrade
   az postgres flexible-server execute \
     --name <postgresServerName> \
     --admin-user <dbOperatorPrincipalName> \
     --querytext "$(cat infra/database/init.sql)" \
     --database-name <POSTGRESQL_DATABASE_NAME>
   ```

4. Verify the grants:

   ```sql
   \dp image_metadata
   ```

   Confirm only the two expected roles appear, with only the privileges
   documented above — no `ALL PRIVILEGES`, no `GRANT OPTION`, and no grants to
   `PUBLIC`.

## Re-running after a schema change

All statements in `init.sql` are idempotent. If the JPA entity changes (new
column, new index), update `init.sql` first (reviewed like any other code
change), then re-run it the same way — it will not error on objects that
already exist, and will not touch existing data.
