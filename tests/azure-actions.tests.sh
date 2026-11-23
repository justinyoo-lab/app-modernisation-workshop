#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./tests/azure-actions.tests.sh.' >&2
    return 2 2>/dev/null || exit 2
fi
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/scripts/install-prerequisites.sh"
CHECK_FAILURES=0
calls=''
logged_in=0
can_prompt_azure() { return 0; }
confirm_azure_action() { [[ "${approved:-0}" == 1 ]]; }
probe() {
    PROBE_CODE=0; PROBE_TEXT=''
    case "$*" in
        'az account show --query state --output tsv')
            if (( logged_in )); then PROBE_TEXT=Enabled; else PROBE_CODE=1; PROBE_TEXT='fixture auth error'; fi ;;
        'az account list --query [].[id,name] --output tsv') PROBE_TEXT=$'id-one\tFirst\nid-two\tSecond' ;;
        'az extension show --name containerapp --query version --output tsv') PROBE_CODE=1 ;;
        'azd auth login --check-status') PROBE_CODE=1 ;;
        *) printf 'Unexpected probe: %s\n' "$*" >&2; exit 1 ;;
    esac
}
az() { calls+="$*;"; logged_in=1; return "${action_failure:-0}"; }
azd() { calls+="azd $*;"; return "${action_failure:-0}"; }
approved=0
prepare_azure_account
prepare_containerapp_extension
prepare_azd_login
[[ -z "$calls" ]]
approved=1
prepare_azure_account <<< id-two
[[ "$calls" == 'login;account set --subscription id-two;' ]]
calls=''
prepare_azure_account <<< invalid
[[ -z "$calls" ]]
prepare_containerapp_extension
prepare_azd_login
[[ "$calls" == 'extension add --name containerapp --upgrade;azd auth login;' ]]
calls=''
action_failure=1
logged_in=0
prepare_azure_account <<< id-one
[[ "$calls" == 'login;' ]]
calls=''
can_prompt_azure() { return 1; }
prepare_azure_account
prepare_containerapp_extension
prepare_azd_login
prepare_azure_provider Microsoft.App
[[ -z "$calls" ]]
source "$ROOT/scripts/install-prerequisites.sh"
can_prompt_azure() { return 0; }
CHECK_FAILURES=0
approved=1
confirm_azure_action() { [[ "$approved" == 1 ]]; }
registered=0
query_failure=0
calls=''
probe() {
    PROBE_CODE="$query_failure"
    if (( registered )); then PROBE_TEXT=Registered; else PROBE_TEXT=NotRegistered; fi
}
az() { calls+="$*;"; registered=1; }
prepare_azure_provider Microsoft.App
[[ "$calls" == 'provider register --namespace Microsoft.App --wait;' ]]
[[ "$CHECK_FAILURES" == 0 ]]
calls=''
prepare_azure_provider Microsoft.App
[[ -z "$calls" ]]
registered=0
query_failure=1
before="$CHECK_FAILURES"
prepare_azure_provider Microsoft.App
[[ -z "$calls" && "$CHECK_FAILURES" == "$((before + 1))" ]]
query_failure=0
confirm_azure_action() { return 1; }
prepare_azure_provider Microsoft.App
[[ -z "$calls" ]]
source "$ROOT/scripts/install-prerequisites.sh"
CI=1
if confirm_azure_action 'must not prompt'; then exit 1; fi
unset CI
preparation=$(
    prepare_azure_account() { printf 'prepare-account\n'; }
    prepare_containerapp_extension() { printf 'prepare-extension\n'; }
    prepare_azd_login() { printf 'prepare-azd\n'; }
    check_azure_identity() { printf 'show-identity\n'; }
    prepare_azure_provider() { printf 'prepare-provider: %s\n' "$1"; }
    probe() { PROBE_CODE=0; PROBE_TEXT=Enabled; }
    prepare_azure_environment
)
[[ "$preparation" == *prepare-account* && "$preparation" == *prepare-extension* &&
   "$preparation" == *show-identity* && "$preparation" == *prepare-azd* &&
   "$preparation" == *'prepare-provider: Microsoft.DBforPostgreSQL'* &&
   "$preparation" != *Microsoft.Sql* ]]
[[ "$(grep -c '^prepare-provider:' <<< "$preparation")" == 6 ]]
no_account=$(
    prepare_azure_account() { :; }
    prepare_containerapp_extension() { :; }
    prepare_azd_login() { :; }
    prepare_azure_provider() { printf 'UNEXPECTED PROVIDER\n'; }
    probe() { PROBE_CODE=1; PROBE_TEXT='auth error'; }
    prepare_azure_environment
)
[[ "$no_account" != *'UNEXPECTED PROVIDER'* ]]
preparation_failed=$(
    prepare_azure_account() { check_result FAIL azure-action 'fixture failure'; }
    prepare_containerapp_extension() { :; }
    prepare_azd_login() { :; }
    probe() { PROBE_CODE=1; PROBE_TEXT='auth error'; }
    if prepare_azure_environment; then printf 'UNEXPECTED SUCCESS\n'; else printf 'EXPECTED FAILURE\n'; fi
)
[[ "$preparation_failed" == *'EXPECTED FAILURE'* && "$preparation_failed" != *'UNEXPECTED SUCCESS'* ]]
can_prompt_azure() { return 0; }
confirm_azure_action() { printf 'UNEXPECTED PROMPT\n' >&2; exit 1; }
prepare_azure_account() { printf 'UNEXPECTED ACCOUNT PREPARATION\n' >&2; exit 1; }
prepare_containerapp_extension() { printf 'UNEXPECTED EXTENSION INSTALL\n' >&2; exit 1; }
prepare_azd_login() { printf 'UNEXPECTED LOGIN\n' >&2; exit 1; }
run_azure_action() { printf 'UNEXPECTED ACTION\n' >&2; exit 1; }
initialize_node_environment() { :; }
check_container() { :; }
check_azure_identity() { :; }
probe() {
    PROBE_CODE=0; PROBE_TEXT=''
    case "$*" in
        'git --version') PROBE_TEXT='git version 2.0.0' ;;
        'node --version') PROBE_TEXT=v22.0.0 ;;
        'modernize --version') PROBE_TEXT='modernize 1.0.76' ;;
        'gh --version') PROBE_TEXT='gh version 2.45.0' ;;
        'gh auth status') PROBE_CODE=0 ;;
        'az version --output json') PROBE_TEXT='{}' ;;
        'az extension show --name containerapp --query version --output tsv') PROBE_CODE=1 ;;
        'az account show --query state --output tsv') PROBE_TEXT=Enabled ;;
        'az provider show '*) PROBE_TEXT=NotRegistered ;;
        'azd version') PROBE_TEXT='azd version 1.37.3' ;;
        'azd auth login --check-status') PROBE_CODE=1 ;;
        *) printf 'Unexpected read-only probe: %s\n' "$*" >&2; exit 1 ;;
    esac
}
CHECK_FAILURES=0
check_common docker
[[ "$CHECK_FAILURES" == 8 ]]
PROBE_CODE=0
probe() { PROBE_CODE=0; PROBE_TEXT=Registered; }
check_azure_provider Microsoft.App
[[ "$CHECK_FAILURES" == 8 ]]
printf 'PASS: Azure action approval, selection, failure and noninteractive cases\n'
