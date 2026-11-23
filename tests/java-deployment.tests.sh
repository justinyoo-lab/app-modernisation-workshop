#!/usr/bin/env bash
set -e
unset CI
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/scripts/terminal-output.sh"
source "$ROOT/scripts/java-deployment.sh"
TEMPORARY="$ROOT/.test-output/deployment-bash.$$.$RANDOM"
mkdir -p "$TEMPORARY"
trap 'rm -rf -- "$TEMPORARY"' EXIT
mkdir -p "$TEMPORARY/app" "$TEMPORARY/tmp"
export TMPDIR="$TEMPORARY/tmp"
printf 'name: fixture\n' > "$TEMPORARY/app/azure.yaml"
printf "SELECT :'web_identity_name', :'worker_identity_name', :'database_name';\n" > "$TEMPORARY/app/users.sql"
printf 'fixture-ca\n' > "$TEMPORARY/app/roots.pem"
export PGSSLROOTCERT="$TEMPORARY/app/roots.pem"
cd "$TEMPORARY/app"
CALLS="$TEMPORARY/calls"
PASSED=0
CASE_NAME=success
jd_interactive() { [[ -z "${CI:-}" && "$CASE_NAME" != noninteractive ]]; }
read() {
    if [[ $# == 2 && "$1" == -r && "$2" == answer ]]; then
        if [[ "$CASE_NAME" == declined ]]; then answer=no; else answer=APPLY; fi
    else builtin read "$@"; fi
}
azd() {
    printf 'azd %s\n' "$*" >> "$CALLS"
    [[ "$CASE_NAME" != env-failure ]] || { printf 'fixture azd failure\n' >&2; return 42; }
    if [[ "$CASE_NAME" == empty-env && "$3" == AZURE_RESOURCE_GROUP ]]; then return; fi
    case "$3" in
        AZURE_SUBSCRIPTION_ID) printf 'subscription-fixture\n' ;;
        AZURE_RESOURCE_GROUP) printf 'rg-fixture\n' ;;
        POSTGRESQL_SERVER) printf 'pg-fixture\n' ;;
        POSTGRESQL_DATABASE) printf 'assets_manager\n' ;;
        POSTGRESQL_ADMIN_NAME) printf 'admin-fixture\n' ;;
        POSTGRESQL_ADMIN_OBJECT_ID) printf 'admin-object\n' ;;
        WEB_CONTAINER_APP_NAME) printf 'web-fixture\n' ;;
        WORKER_CONTAINER_APP_NAME) printf 'worker-fixture\n' ;;
        *) printf 'Unexpected azd lookup\n' >&2; return 99 ;;
    esac
}
az() {
    local call="$*" app=''
    printf 'az %s\n' "$call" >> "$CALLS"
    [[ "$CASE_NAME" != query-failure ]] || { printf 'fixture query failure\n' >&2; return 42; }
    case "$call" in
        'account show '*) printf 'subscription-fixture\n' ;;
        'ad signed-in-user show '*)
            if [[ "$CASE_NAME" == wrong-admin ]]; then printf 'other-object\n'; else printf 'admin-object\n'; fi ;;
        'account get-access-token '*)
            [[ "$CASE_NAME" == empty-token ]] || printf 'fixture-secret-token\n' ;;
        'postgres flexible-server show '*) printf 'pg-fixture.postgres.database.azure.com\n' ;;
        *'firewall-rule list '*)
            if [[ "$CASE_NAME" == existing-rule ]]; then printf '203.0.113.7\t203.0.113.7\n'
            elif [[ "$CASE_NAME" == conflicting-rule ]]; then printf '203.0.113.1\t203.0.113.10\n'; fi ;;
        *'firewall-rule create '*) : ;;
        'containerapp show '*identity.userAssignedIdentities*)
            case "$CASE_NAME" in
                empty-identity) : ;;
                multiple-identities) printf '/ids/one\n/ids/two\n' ;;
                *) printf '/ids/single\n' ;;
            esac ;;
        'identity show '*) [[ "$CASE_NAME" == empty-name ]] || printf 'identity-fixture\n' ;;
        'containerapp show '*)
            while (( $# )); do
                if [[ "$1" == --name ]]; then app="$2"; break; fi
                shift
            done
            if [[ "$CASE_NAME" == stale-revision ]]; then printf 'Succeeded\tlatest\tprevious\t'
            else printf 'Succeeded\tlatest\tlatest\t'; fi
            if [[ "$app" == web-fixture || "$CASE_NAME" == worker-ingress ]]; then printf 'True\t8080\tweb.example.test\n'
            else printf 'None\tNone\tNone\n'; fi ;;
        'containerapp revision show '*)
            if [[ "$CASE_NAME" == unhealthy ]]; then printf 'True\tUnhealthy\tRunning\n'
            elif [[ "$CASE_NAME" == web-scaled-down && "$call" == *web-fixture* ]]; then printf 'True\tHealthy\tScaleToZero\n'
            else printf 'True\tHealthy\tRunning\n'; fi ;;
        'containerapp logs show '*) printf 'fixture system event\n' ;;
        *) printf 'Unexpected az call: %s\n' "$call" >&2; return 99 ;;
    esac
}
psql() {
    printf 'psql %s\n' "$*" >> "$CALLS"
    [[ "${PGPASSWORD:-}" == fixture-secret-token && "$PGSSLMODE" == verify-full && "$*" != *fixture-secret-token* ]] || return 99
    [[ "$CASE_NAME" != sql-failure ]] || return 42
}
curl() {
    local output=''
    [[ "$CASE_NAME" != download-failure && "$CASE_NAME" != http-failure ]] || return 42
    while (( $# )); do
        if [[ "$1" == --output ]]; then output="$2"; shift; fi
        shift
    done
    if [[ "$output" == /dev/null ]]; then
        if [[ "$CASE_NAME" == http-redirect ]]; then printf 302; else printf 200; fi
    else printf 'fixture DER\n' > "$output"; fi
}
openssl() {
    local output=''
    [[ "$CASE_NAME" != conversion-failure ]] || return 42
    while (( $# )); do
        if [[ "$1" == -out ]]; then output="$2"; shift; fi
        shift
    done
    printf '%s\n' '-----BEGIN CERTIFICATE-----' fixture '-----END CERTIFICATE-----' > "$output"
}
run_case() {
    local expected="$1" result
    shift
    set +e
    (jd_main "$@") > "$TEMPORARY/out" 2> "$TEMPORARY/err"
    result=$?
    set -e
    if [[ "$expected" == pass && "$result" != 0 || "$expected" == fail && "$result" == 0 ]]; then
        cat "$TEMPORARY/out" "$TEMPORARY/err" >&2
        printf 'FAILED: %s / %s\n' "$CASE_NAME" "$*" >&2
        exit 1
    fi
    if grep -q fixture-secret-token "$TEMPORARY/out" "$TEMPORARY/err" "$CALLS"; then
        printf 'FAILED: token leaked\n' >&2; exit 1
    fi
    PASSED=$((PASSED + 1))
}
run_case pass info
for CASE_NAME in env-failure empty-env query-failure empty-identity multiple-identities empty-name; do run_case fail info; done
CASE_NAME=success
for ip in '' 0.0.0.0 255.255.255.255 256.1.1.1 1.2.3 1.2.3.04 ::1; do run_case fail firewall --client-ip "$ip"; done
for CASE_NAME in declined noninteractive conflicting-rule; do run_case fail firewall --client-ip 203.0.113.7; done
if grep -q 'firewall-rule create' "$CALLS"; then exit 1; fi
CASE_NAME=success
run_case pass firewall --client-ip 203.0.113.7
CASE_NAME=existing-rule
run_case pass firewall --client-ip 203.0.113.7
[[ "$(grep -c 'firewall-rule create' "$CALLS")" == 1 ]]
CASE_NAME=success
CI=1 run_case fail firewall --client-ip 203.0.113.8
CASE_NAME=success
run_case pass users --sql-path users.sql
grep -q 'psql .*--dbname postgres ' "$CALLS"
run_case pass schema --sql-path users.sql
grep -q 'psql .*--dbname assets_manager ' "$CALLS"
grep -q 'psql .*--set verify_schema=true .*--file .*java-db-permissions.sql' "$CALLS"
for CASE_NAME in sql-failure empty-token wrong-admin declined noninteractive; do run_case fail schema --sql-path users.sql; done
CASE_NAME=success
printf "\\\\prompt 'Web name' web_identity_name\n" > legacy.sql
run_case fail users --sql-path legacy.sql
for CASE_NAME in stale-revision unhealthy worker-ingress http-failure http-redirect; do run_case fail status; done
CASE_NAME=success
run_case pass status
CASE_NAME=web-scaled-down
run_case pass status
CASE_NAME=success
run_case pass certificate
certificate_path=$(cat "$TEMPORARY/out")
[[ -s "$certificate_path" && "$(grep -c 'BEGIN CERTIFICATE' "$certificate_path")" == 2 ]]
[[ "$(wc -l < "$TEMPORARY/out" | tr -d ' ')" == 1 ]]
rm -- "$certificate_path"
rmdir -- "${certificate_path%/*}"
for CASE_NAME in download-failure conversion-failure; do
    run_case fail certificate
    [[ ! -s "$TEMPORARY/out" ]]
done
[[ -z "$(ls -A "$TMPDIR")" ]]
printf 'PASS: %s Java deployment helper cases (mocked tools only)\n' "$PASSED"
