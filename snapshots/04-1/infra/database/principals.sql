-- Run only against the postgres database after separate operator approval.
-- Replace the placeholders with the verified managed identity names.
-- Existing principals must be reviewed before running these statements.
\set ON_ERROR_STOP on
SELECT * FROM pgaadauth_create_principal('<WEB_MANAGED_IDENTITY_NAME>', false, false);
SELECT * FROM pgaadauth_create_principal('<WORKER_MANAGED_IDENTITY_NAME>', false, false);
