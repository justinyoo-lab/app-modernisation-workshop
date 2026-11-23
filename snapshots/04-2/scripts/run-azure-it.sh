#!/usr/bin/env bash

ait_fail() { printf '[FAIL] %s\n' "$*" >&2; return 1; }
ait_interactive() { [[ -z "${CI:-}" && -t 0 && -t 1 ]]; }
ait_value() {
    local value
    value=$(azd env get-value "$1" 2>/dev/null) || { ait_fail "azd lookup failed: $1"; return 1; }
    case "$value" in
        ''|*[[:space:]]*|\<*\>) ait_fail "Missing or invalid azd value: $1"; return 1 ;;
    esac
    printf '%s' "$value"
}
ait_account() {
    local value
    value=$(az account show --query "$1" --output tsv 2>/dev/null) || { ait_fail "Azure CLI account lookup failed: $1"; return 1; }
    case "$value" in ''|*[[:space:]]*|\<*\>) ait_fail "Missing or invalid Azure CLI account value: $1"; return 1 ;; esac
    printf '%s' "$value"
}
ait_namespace() {
    local name
    name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    name="${name%.servicebus.windows.net}"
    [[ "$name" =~ ^[a-z0-9][a-z0-9-]{4,48}[a-z0-9]$ ]] || return 1
    printf '%s.servicebus.windows.net' "$name"
}
ait_check_report() {
    local file="$1"
    [[ -f "$file" ]] || { ait_fail "Missing test result: $file"; return 1; }
    grep '<testsuite ' "$file" | grep -q 'tests="1"' &&
        grep '<testsuite ' "$file" | grep -q 'failures="0"' &&
        grep '<testsuite ' "$file" | grep -q 'errors="0"' &&
        grep '<testsuite ' "$file" | grep -q 'skipped="0"' ||
        { ait_fail "Test result is incomplete, skipped, or failed: $file"; return 1; }
}
ait_main() (
    local script_dir app_dir name value account_type account_user subscription test_namespace app_namespace answer root reports class
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1
    app_dir=$(cd -- "$script_dir/.." && pwd -P) || exit 1
    [[ "$(pwd -P)" == "$app_dir" && -f ./mvnw && -f ./azure.yaml ]] || { ait_fail 'Run this script from the app root.'; exit 1; }
    ait_interactive || { ait_fail 'Interactive approval is required; CI and redirected terminals are not allowed.'; exit 1; }
    command -v az >/dev/null 2>&1 && command -v azd >/dev/null 2>&1 || { ait_fail 'Azure CLI and azd are required; nothing was installed.'; exit 1; }
    grep -q '<id>azure-it</id>' pom.xml && grep -q '<id>azure-it</id>' worker/pom.xml ||
        { ait_fail 'The azure-it Maven profile is missing.'; exit 1; }
    export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no AZURE_AUTO_UPGRADE_ENABLE=false
    account_type=$(ait_account user.type) || exit 1
    account_user=$(ait_account user.name) || exit 1
    subscription=$(ait_account id) || exit 1
    [[ "$account_type" == user ]] || { ait_fail 'Only an Azure CLI user account is supported.'; exit 1; }
    for name in AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP AZURE_IT_PG_HOST AZURE_IT_PG_DATABASE \
        AZURE_IT_BLOB_ENDPOINT AZURE_IT_BLOB_CONTAINER AZURE_IT_SERVICEBUS_NAMESPACE AZURE_IT_SERVICEBUS_QUEUE \
        AZURE_IT_APP_SERVICEBUS_NAMESPACE AZURE_IT_APP_SERVICEBUS_QUEUE; do
        value=$(ait_value "$name") || exit 1
        export "$name=$value"
    done
    [[ "$(printf '%s' "$subscription" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$AZURE_SUBSCRIPTION_ID" | tr '[:upper:]' '[:lower:]')" ]] ||
        { ait_fail 'Azure CLI and azd subscriptions differ; no subscription was changed.'; exit 1; }
    export AZURE_IT_PG_USER="$account_user"
    test_namespace=$(ait_namespace "$AZURE_IT_SERVICEBUS_NAMESPACE") || { ait_fail 'Invalid test namespace.'; exit 1; }
    app_namespace=$(ait_namespace "$AZURE_IT_APP_SERVICEBUS_NAMESPACE") || { ait_fail 'Invalid app namespace.'; exit 1; }
    if [[ "$test_namespace" == "$app_namespace" && "$(printf '%s' "$AZURE_IT_SERVICEBUS_QUEUE" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$AZURE_IT_APP_SERVICEBUS_QUEUE" | tr '[:upper:]' '[:lower:]')" ]]; then
        ait_fail 'Test queue is the app queue.'; exit 1
    fi
    [[ "$AZURE_IT_PG_HOST" =~ ^[a-z0-9][a-z0-9-]*\.postgres\.database\.azure\.com$ && "$AZURE_IT_PG_DATABASE" =~ ^[A-Za-z0-9_-]+$ &&
       "$AZURE_IT_BLOB_ENDPOINT" =~ ^https://[a-z0-9]{3,24}\.blob\.core\.windows\.net/?$ &&
       "$AZURE_IT_BLOB_CONTAINER" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ &&
       "$AZURE_IT_SERVICEBUS_QUEUE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && ${#AZURE_IT_SERVICEBUS_QUEUE} -le 260 &&
       "$AZURE_IT_APP_SERVICEBUS_QUEUE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && ${#AZURE_IT_APP_SERVICEBUS_QUEUE} -le 260 ]] ||
        { ait_fail 'Invalid target format; no test was run.'; exit 1; }
    printf 'User / PostgreSQL user: %s\nSubscription: %s\nResource group: %s\n' "$account_user" "$subscription" "$AZURE_RESOURCE_GROUP"
    printf 'PostgreSQL: %s / %s\nBlob: %s / %s\nTest queue: %s / %s\nApp queue: %s / %s\n' \
        "$AZURE_IT_PG_HOST" "$AZURE_IT_PG_DATABASE" "$AZURE_IT_BLOB_ENDPOINT" "$AZURE_IT_BLOB_CONTAINER" \
        "$test_namespace" "$AZURE_IT_SERVICEBUS_QUEUE" "$app_namespace" "$AZURE_IT_APP_SERVICEBUS_QUEUE"
    printf '%s\n' 'Writes: one new DB row, private test blobs and one message in a session-enabled test queue.'
    printf '%s\n' 'Reads: the test row and blobs, container properties, and only the new message session.'
    printf '%s\n' 'Test data is retained. Verify the DB user, access, network, costs and manual cleanup instructions.'
    printf 'Type RUN to approve these targets and changes: '
    IFS= read -r answer || { ait_fail 'Approval was not received.'; exit 1; }
    [[ "$answer" == RUN ]] || { ait_fail 'Cancelled; no tests were run.'; exit 1; }
    source ../scripts/use-java.sh --jdk 25 || { ait_fail 'JDK 25 selection failed.'; exit 1; }
    mkdir -p worker/target/azure-it-reports || { ait_fail 'Cannot create report parent.'; exit 1; }
    root=$(mktemp -d worker/target/azure-it-reports/run.XXXXXXXX) || { ait_fail 'Cannot create unique report location.'; exit 1; }
    reports="$root/reports"
    export AZURE_IT_APPROVED=YES
    printf '[INFO] New reports: %s\n' "$reports"
    ./mvnw -Pazure-it -pl web,worker -am -o "-Dazure.it.report.dir=$app_dir/$reports" verify ||
        { ait_fail 'Maven or Azure integration tests failed.'; exit 1; }
    for class in PostgresAzureIT BlobAzureIT ServiceBusAzureIT; do
        ait_check_report "$reports/TEST-com.microsoft.migration.assets.worker.azureit.$class.xml" || exit 1
    done
    printf '%s\n' '[PASS] PostgreSQL, Blob and Service Bus Azure integration tests succeeded.'
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    ait_main "$@"
fi
