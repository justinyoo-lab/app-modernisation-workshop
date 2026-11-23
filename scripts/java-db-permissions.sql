\echo 'Checking database, session and effective application permissions'
SELECT current_database(), session_user, current_user;
\du
\dt
\dp

SELECT role_name,
       has_database_privilege(role_name, :'database_name', 'CONNECT') AS can_connect,
       has_schema_privilege(role_name, 'public', 'USAGE') AS can_use,
       has_schema_privilege(role_name, 'public', 'CREATE') AS can_create
FROM (VALUES (:'web_identity_name'), (:'worker_identity_name')) AS apps(role_name);

SELECT current_database() = :'database_name'
       AND bool_and(has_database_privilege(role_name, :'database_name', 'CONNECT')
                    AND has_schema_privilege(role_name, 'public', 'USAGE')
                    AND NOT has_schema_privilege(role_name, 'public', 'CREATE')) AS valid
FROM (VALUES (:'web_identity_name'), (:'worker_identity_name')) AS apps(role_name)
\gset roles_
\if :roles_valid
\else
    DO $check$ BEGIN
        RAISE EXCEPTION 'Database, CONNECT, USAGE or schema CREATE permissions differ from the workshop contract.';
    END; $check$;
\endif

\if :verify_schema
    SELECT role_name,
           has_table_privilege(role_name, 'public.image_metadata', 'SELECT') AS can_select,
           has_table_privilege(role_name, 'public.image_metadata', 'INSERT') AS can_insert,
           has_table_privilege(role_name, 'public.image_metadata', 'UPDATE') AS can_update,
           has_table_privilege(role_name, 'public.image_metadata', 'DELETE') AS can_delete
    FROM (VALUES (:'web_identity_name'), (:'worker_identity_name')) AS apps(role_name);

    SELECT bool_and(
        has_table_privilege(role_name, 'public.image_metadata', 'SELECT')
        AND has_table_privilege(role_name, 'public.image_metadata', 'UPDATE')
        AND has_table_privilege(role_name, 'public.image_metadata', 'INSERT') = is_web
        AND has_table_privilege(role_name, 'public.image_metadata', 'DELETE') = is_web
        AND NOT has_table_privilege(role_name, 'public.image_metadata', 'TRUNCATE')
        AND NOT has_table_privilege(role_name, 'public.image_metadata', 'REFERENCES')
        AND NOT has_table_privilege(role_name, 'public.image_metadata', 'TRIGGER')) AS valid
    FROM (VALUES (:'web_identity_name', true), (:'worker_identity_name', false)) AS apps(role_name, is_web)
    \gset tables_
    \if :tables_valid
    \else
        DO $check$ BEGIN
            RAISE EXCEPTION 'Effective table permissions differ from the workshop contract.';
        END; $check$;
    \endif

    SELECT pg_get_userbyid(relowner) AS table_owner,
           pg_get_userbyid(relowner) = current_user AS valid
    FROM pg_class WHERE oid = 'public.image_metadata'::regclass
    \gset owner_
    \echo 'Table owner:' :owner_table_owner
    \if :owner_valid
    \else
        DO $check$ BEGIN
            RAISE EXCEPTION 'The table must be owned by the initializing administrator.';
        END; $check$;
    \endif
\endif
