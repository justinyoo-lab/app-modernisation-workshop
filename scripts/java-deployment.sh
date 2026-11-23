#!/usr/bin/env bash

jd_message() { workshop_status_printf '%s\n' "[$1] $2" >&2; }
jd_fail() { jd_message FAIL "$*"; return 1; }
jd_require() { command -v "$1" >/dev/null 2>&1 || jd_fail "Required tool not found: $1"; }

jd_tool() {
    local tool="$1" result
    shift
    "$tool" "$@" || { result=$?; jd_message FAIL "$tool failed (exit code $result)."; return "$result"; }
}

jd_value() {
    local value
    value=$(jd_tool azd env get-value "$1") || return
    case "$value" in
        ''|*$'\n'*|*$'\r'*) jd_fail "Missing or multiline azd value: $1"; return 1 ;;
    esac
    printf '%s\n' "$value"
}

jd_context() {
    [[ -f azure.yaml ]] || { jd_fail 'Run this helper from the application root containing azure.yaml.'; return 1; }
    jd_require azd && jd_require az || return
    export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
    export AZURE_AUTO_UPGRADE_ENABLE=false
    JD_SUBSCRIPTION=$(jd_value AZURE_SUBSCRIPTION_ID) || return
    JD_GROUP=$(jd_value AZURE_RESOURCE_GROUP) || return
    jd_tool az account show --subscription "$JD_SUBSCRIPTION" --query id --output tsv >/dev/null || return
    jd_message INFO "Subscription: $JD_SUBSCRIPTION / Resource group: $JD_GROUP"
}

jd_interactive() { [[ -z "${CI:-}" && -t 0 && -t 1 ]]; }

jd_confirm() {
    local answer
    jd_interactive || { jd_fail 'Changes require an interactive terminal; CI/noninteractive execution is not allowed.'; return 1; }
    jd_message WARN "$1"
    printf '%s' 'Type APPLY to continue: ' >&2
    IFS= read -r answer || return 1
    [[ "$answer" == APPLY ]] || { jd_fail 'Cancelled; no change was requested.'; return 1; }
}

jd_ipv4() {
    local part
    local -a parts
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do
        [[ ${#part} -le 3 && ( "$part" == 0 || "$part" != 0* ) ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done
    [[ "$1" != 0.0.0.0 && "$1" != 255.255.255.255 ]]
}

jd_identity() {
    local id name
    id=$(jd_tool az containerapp show --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --name "$1" --query 'identity.userAssignedIdentities | keys(@)' --output tsv) || return
    case "$id" in ''|*[[:space:]]*) jd_fail "$1 must have exactly one user-assigned identity."; return 1 ;; esac
    name=$(jd_tool az identity show --ids "$id" --query name --output tsv) || return
    case "$name" in ''|*$'\n'*|*$'\r'*) jd_fail "$1 returned no single identity name."; return 1 ;; esac
    printf '%s\n' "$name"
}

jd_db_info() {
    local web worker
    JD_SERVER=$(jd_value POSTGRESQL_SERVER) || return
    JD_DATABASE=$(jd_value POSTGRESQL_DATABASE) || return
    JD_ADMIN=$(jd_value POSTGRESQL_ADMIN_NAME) || return
    JD_HOST=$(jd_tool az postgres flexible-server show --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --name "$JD_SERVER" --query fullyQualifiedDomainName --output tsv) || return
    [[ "$JD_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { jd_fail 'Invalid PostgreSQL FQDN.'; return 1; }
    web=$(jd_value WEB_CONTAINER_APP_NAME) || return
    worker=$(jd_value WORKER_CONTAINER_APP_NAME) || return
    JD_WEB_IDENTITY=$(jd_identity "$web") || return
    JD_WORKER_IDENTITY=$(jd_identity "$worker") || return
    printf 'Server: %s\nHost: %s\nAdministrator: %s\nWeb: %s\nWorker: %s\nDatabase: %s\n' \
        "$JD_SERVER" "$JD_HOST" "$JD_ADMIN" "$JD_WEB_IDENTITY" "$JD_WORKER_IDENTITY" "$JD_DATABASE"
}

jd_certificate() (
    set -e
    local directory complete=false
    jd_require curl
    jd_require openssl
    directory=$(mktemp -d)
    trap 'if [[ "$complete" != true ]]; then rm -f -- "$directory/digicert.der" "$directory/microsoft.der" "$directory/digicert.pem" "$directory/microsoft.pem" "$directory/roots.pem"; rmdir -- "$directory"; fi' EXIT
    jd_message INFO 'Downloading Azure PostgreSQL root CAs from DigiCert and Microsoft.'
    jd_tool curl --fail --silent --show-error --location --max-time 30 --output "$directory/digicert.der" 'https://cacerts.digicert.com/DigiCertGlobalRootG2.crt'
    jd_tool curl --fail --silent --show-error --location --max-time 30 --output "$directory/microsoft.der" 'https://www.microsoft.com/pkiops/certs/Microsoft%20RSA%20Root%20Certificate%20Authority%202017.crt'
    jd_tool openssl x509 -inform DER -in "$directory/digicert.der" -out "$directory/digicert.pem"
    jd_tool openssl x509 -inform DER -in "$directory/microsoft.der" -out "$directory/microsoft.pem"
    cat "$directory/digicert.pem" "$directory/microsoft.pem" > "$directory/roots.pem"
    [[ -s "$directory/roots.pem" ]] || { jd_fail 'The CA bundle is empty.'; exit 1; }
    rm -- "$directory/digicert.der" "$directory/microsoft.der" "$directory/digicert.pem" "$directory/microsoft.pem"
    complete=true
    printf '%s\n' "$directory/roots.pem"
)

jd_firewall() {
    local ip="$1" name existing
    jd_ipv4 "$ip" || { jd_fail 'Supply one unambiguous IPv4 address, not an all-Azure or all-internet address.'; return 1; }
    jd_context || return
    JD_SERVER=$(jd_value POSTGRESQL_SERVER) || return
    name="allow-local-${ip//./-}"
    existing=$(jd_tool az postgres flexible-server firewall-rule list --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --server-name "$JD_SERVER" --query "[?name=='$name'].[startIpAddress,endIpAddress]" --output tsv) || return
    if [[ -n "$existing" ]]; then
        [[ "$existing" == "$ip"$'\t'"$ip" ]] || { jd_fail "Rule $name exists with a different range; it will not be overwritten."; return 1; }
        jd_message PASS "The individual client IP is already allowed: $ip"
        return
    fi
    jd_confirm "Add $name on PostgreSQL $JD_SERVER for $ip only? Existing rules will be preserved." || return
    jd_tool az postgres flexible-server firewall-rule create --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --server-name "$JD_SERVER" --name "$name" --start-ip-address "$ip" --end-ip-address "$ip" --output none || return
    jd_message PASS "Registered client IP: $ip"
}

jd_sql() (
    set -e
    local phase="$1" sql="$2" database signed_in admin_id verify_schema=false verification
    jd_context
    jd_require psql
    [[ -f "$sql" && -r "$sql" ]] || { jd_fail "SQL file not found or unreadable: $sql"; exit 1; }
    if grep -Eq '^[[:space:]]*\\prompt|migration_identity' "$sql"; then
        jd_fail 'Review the SQL in workshop step 5: use psql variables, no \prompt or migration identity. No SQL was run.'
        exit 1
    fi
    [[ -n "${PGSSLROOTCERT:-}" && -s "$PGSSLROOTCERT" ]] || { jd_fail 'Set PGSSLROOTCERT to the prepared CA bundle first.'; exit 1; }
    jd_db_info
    signed_in=$(jd_tool az ad signed-in-user show --query id --output tsv)
    admin_id=$(jd_value POSTGRESQL_ADMIN_OBJECT_ID)
    [[ -n "$signed_in" && "$signed_in" == "$admin_id" ]] || { jd_fail 'The signed-in Azure CLI user is not the reviewed Entra administrator.'; exit 1; }
    database="$JD_DATABASE"
    [[ "$phase" != users ]] || database=postgres
    [[ "$phase" != schema ]] || verify_schema=true
    verification="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/java-db-permissions.sql"
    jd_confirm "Execute reviewed SQL $sql on $JD_HOST / $database as $JD_ADMIN? This changes DB objects and permissions; it is not automatically undone or retried."
    trap 'unset PGPASSWORD' EXIT
    PGPASSWORD=$(jd_tool az account get-access-token --subscription "$JD_SUBSCRIPTION" --resource-type oss-rdbms --query accessToken --output tsv)
    [[ -n "$PGPASSWORD" && "$PGPASSWORD" != *[[:space:]]* ]] || { jd_fail 'Token acquisition did not return one token.'; exit 1; }
    export PGPASSWORD PGSSLMODE=verify-full
    if ! jd_tool psql --no-psqlrc --no-password --host "$JD_HOST" --dbname "$database" --username "$JD_ADMIN" \
        --set ON_ERROR_STOP=on --set "web_identity_name=$JD_WEB_IDENTITY" --set "worker_identity_name=$JD_WORKER_IDENTITY" \
        --set "database_name=$JD_DATABASE" --set "verify_schema=$verify_schema" --file "$sql" --file "$verification"; then
        jd_fail 'SQL or permission verification failed; changes may be partially applied. Inspect the database before retrying.'
        exit 1
    fi
    jd_message PASS 'SQL and effective permission checks completed. Review the printed roles and grants for unexpected inheritance.'
)

jd_status() {
    local app role row state latest ready external port fqdn revision active health running code failed=0 web_url=''
    jd_context || return
    jd_require curl || return
    for role in WEB WORKER; do
        app=$(jd_value "${role}_CONTAINER_APP_NAME") || return
        row=$(jd_tool az containerapp show --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --name "$app" \
            --query '[[properties.provisioningState,properties.latestRevisionName,properties.latestReadyRevisionName,properties.configuration.ingress.external,properties.configuration.ingress.targetPort,properties.configuration.ingress.fqdn]]' --output tsv) || return
        IFS=$'\t' read -r state latest ready external port fqdn <<< "$row"
        [[ -n "$latest" && "$latest" != None ]] || { jd_fail "$app has no latest revision."; return 1; }
        revision=$(jd_tool az containerapp revision show --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --name "$app" --revision "$latest" \
            --query '[[properties.active,properties.healthState,properties.runningState]]' --output tsv) || return
        IFS=$'\t' read -r active health running <<< "$revision"
        jd_message INFO "$app: provisioning=$state latest=$latest ready=$ready active=$active health=$health running=$running"
        if [[ "$state" != Succeeded || "$latest" != "$ready" || "$health" != Healthy || ! "$active" =~ ^([Tt]rue)$ ]]; then failed=1; fi
        if [[ "$running" != Running && ! ( "$role" == WEB && "$running" == ScaleToZero ) ]]; then failed=1; fi
        if [[ "$role" == WEB ]]; then
            if [[ ! "$external" =~ ^([Tt]rue)$ || "$port" != 8080 || ! "$fqdn" =~ ^[A-Za-z0-9.-]+$ ]]; then failed=1
            else web_url="https://$fqdn"; fi
        elif [[ "$external" != None || "$port" != None || "$fqdn" != None ]]; then
            jd_message FAIL 'Worker ingress must be disabled.'
            failed=1
        fi
        jd_tool az containerapp logs show --subscription "$JD_SUBSCRIPTION" --resource-group "$JD_GROUP" --name "$app" --type system --tail 20 || return
    done
    if [[ -n "$web_url" ]]; then
        jd_message INFO "Checking web HTTP availability: $web_url"
        code=$(jd_tool curl --fail --silent --show-error --max-time 30 --output /dev/null --write-out '%{http_code}' "$web_url") || failed=1
        [[ "$code" =~ ^2[0-9][0-9]$ ]] || failed=1
    fi
    jd_message MANUAL 'Upload, DB permissions, private Blob access, Service Bus and worker processing require separate approved integration/E2E tests.'
    (( failed == 0 )) || { jd_fail 'Deployment readiness or HTTP availability checks failed.'; return 1; }
    jd_message PASS 'Latest revisions, ingress and HTTP availability checks passed; end-to-end functionality is not verified.'
}

jd_main() (
    set -eo pipefail
    local action="$1" value=''
    shift
    if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
        printf '%s\n' "Run from the application root. Action: $action. Firewall: --client-ip IPv4. SQL: [--sql-path FILE]. Mutating actions require interactive approval."
        exit 0
    fi
    case "$action" in
        firewall) [[ $# == 2 && "$1" == --client-ip ]] || { jd_fail 'Usage: --client-ip IPv4'; exit 2; }; value="$2" ;;
        users|schema)
            if [[ $# == 0 ]]; then
                if [[ "$action" == users ]]; then value=infra/db/bootstrap-identities.sql; else value=infra/db/initialize-image-metadata.sql; fi
            elif [[ $# == 2 && "$1" == --sql-path ]]; then value="$2"
            else jd_fail 'Usage: [--sql-path FILE]'; exit 2; fi ;;
        *) [[ $# == 0 ]] || { jd_fail 'Unknown arguments.'; exit 2; } ;;
    esac
    case "$action" in
        firewall) jd_firewall "$value" ;;
        certificate) jd_certificate ;;
        info) jd_context; jd_db_info ;;
        users|schema) jd_sql "$action" "$value" ;;
        status) jd_status ;;
        *) jd_fail 'Unknown deployment action.'; exit 2 ;;
    esac
)
