-- =============================================================================
-- infra/database/init.sql
--
-- Schema-initialization-ONLY artifact for the assets-manager application
-- database on Azure Database for PostgreSQL Flexible Server.
--
-- DO NOT RUN THIS SCRIPT AS PART OF THE MODERNIZATION PLAN OR AUTOMATICALLY.
-- It is a separate, reviewable procedure that a human DATABASE OPERATOR runs
-- manually, after the infra/main.bicep deployment has completed and after the
-- operator has reviewed this file. See infra/database/README.md for the
-- required pre-reqs and exact commands.
--
-- Scope:
--   - Creates the application schema objects used by Spring Data JPA
--     (JpaRepository<ImageMetadata, String>, see web/worker
--     model/ImageMetadata.java) and grants least-privilege, database-level
--     access to the two workload managed identities.
--   - Does NOT migrate or copy any existing data (local/dev files, prior
--     PostgreSQL rows, or S3 objects). No INSERT/COPY statements are
--     included.
--   - Does NOT create or modify any Azure resource (no ARM/control-plane
--     operations). Database-level GRANTs here are intentionally separate
--     from the ARM role assignments (AcrPull, Service Bus Data
--     Sender/Receiver, Storage Blob Data Contributor) defined in the Bicep
--     modules; a PostgreSQL GRANT never implies any ARM permission and vice
--     versa.
--
-- Idempotency: every statement below is safe to re-run (uses IF NOT EXISTS /
-- conditional DO blocks) so the operator can re-apply it after a schema
-- change without manually tracking whether it already ran.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 1. Application schema: image_metadata
--    Mirrors the JPA entity web/worker: model/ImageMetadata.java
--    (id, filename, content_type, size, s3_key, s3_url, thumbnail_key,
--     thumbnail_url, uploaded_at, updated_at).
--    NOTE: in normal application operation Hibernate's
--    "spring.jpa.hibernate.ddl-auto=update" setting (see application.properties)
--    would create/update this table automatically on first non-dev-profile
--    startup. This script exists so the schema can be reviewed and created
--    explicitly and deterministically by an operator BEFORE the application
--    is ever granted broader runtime privileges than strictly necessary, and
--    so environments that disable Hibernate auto-DDL in production still have
--    a reviewable way to initialize the schema.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS image_metadata (
    id              VARCHAR(255) PRIMARY KEY,
    filename        VARCHAR(255) NOT NULL,
    content_type    VARCHAR(255),
    size            BIGINT,
    s3_key          VARCHAR(512) NOT NULL,
    s3_url          VARCHAR(1024),
    thumbnail_key   VARCHAR(512),
    thumbnail_url   VARCHAR(1024),
    uploaded_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_image_metadata_s3_key ON image_metadata (s3_key);

-- -----------------------------------------------------------------------------
-- 2. Least-privilege database-level principals for the workload managed
--    identities.
--
--    Replace <WEB_MANAGED_IDENTITY_NAME> / <WORKER_MANAGED_IDENTITY_NAME>
--    below with the actual values from the Bicep deployment outputs
--    (WEB_MANAGED_IDENTITY_NAME / WORKER_MANAGED_IDENTITY_NAME), which are
--    also the values the application's POSTGRESQL_USERNAME environment
--    variable is set to. These names become PostgreSQL ROLE names once
--    created via "SELECT * FROM pgaadauth_create_principal(...)" (Microsoft
--    Entra-only auth; no password is ever created, consistent with
--    activeDirectoryAuth=Enabled / passwordAuth=Disabled on the Flexible
--    Server).
--
--    These two application roles are DISTINCT from:
--      - the dbOperatorPrincipalName / dbOperatorObjectId operator identity
--        running this very script (that operator is the server's Entra
--        admin, an elevated role never used by the running application), and
--      - any ARM/control-plane role assignment (AcrPull, Service Bus, Blob
--        Storage) defined in the Bicep modules.
-- -----------------------------------------------------------------------------

-- Create (or no-op if already present) the Microsoft Entra-backed database
-- roles for the two workload managed identities. is_admin := false ensures
-- these are ordinary, non-administrative database roles.
SELECT * FROM pgaadauth_create_principal('<WEB_MANAGED_IDENTITY_NAME>', false, false);
SELECT * FROM pgaadauth_create_principal('<WORKER_MANAGED_IDENTITY_NAME>', false, false);

-- web: full CRUD on image_metadata (uploads create rows; deletes remove rows;
-- list/view reads rows) but no DDL/schema-ownership rights.
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO "<WEB_MANAGED_IDENTITY_NAME>";

-- worker: only needs to update thumbnail_key/thumbnail_url after processing,
-- and to read rows to find the matching original key; no INSERT/DELETE
-- (worker never creates or removes image_metadata rows in the current
-- design) and no DDL rights.
GRANT SELECT, UPDATE ON image_metadata TO "<WORKER_MANAGED_IDENTITY_NAME>";

-- Neither role is granted USAGE on the schema's CREATE privilege, ownership,
-- or any other database/role beyond the single table and index above.

-- =============================================================================
-- End of schema-initialization-only script. No data migration statements are
-- included above, and none should be added without a separate, explicitly
-- approved task per the modernization plan's verification gates.
-- =============================================================================
