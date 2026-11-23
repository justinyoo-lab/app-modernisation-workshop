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
-- required prerequisites and execution order.
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
-- CREATE TABLE IF NOT EXISTS does not migrate an existing schema.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 1. Application schema: image_metadata
--    Mirrors the JPA entity web/worker: model/ImageMetadata.java
--    (id, filename, content_type, size, s3_key, s3_url, thumbnail_key,
--     thumbnail_url, uploaded_at, last_modified).
--    Hibernate validates the schema but does not modify it.
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
    last_modified   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_image_metadata_s3_key ON image_metadata (s3_key);

CREATE TABLE IF NOT EXISTS image_processing_outbox (
    id              VARCHAR(255) PRIMARY KEY,
    blob_key        VARCHAR(512) NOT NULL,
    content_type    VARCHAR(255),
    storage_type    VARCHAR(255) NOT NULL,
    destination     VARCHAR(255) NOT NULL,
    size            BIGINT NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    next_attempt_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2. Least-privilege grants for the previously created workload principals.
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

-- web: full CRUD on image_metadata (uploads create rows; deletes remove rows;
-- list/view reads rows) but no DDL/schema-ownership rights.
GRANT SELECT, INSERT, UPDATE, DELETE ON image_metadata TO "<WEB_MANAGED_IDENTITY_NAME>";
GRANT SELECT, INSERT, UPDATE, DELETE ON image_processing_outbox TO "<WEB_MANAGED_IDENTITY_NAME>";

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
