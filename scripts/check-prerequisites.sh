#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./scripts/check-prerequisites.sh.' >&2
    return 2 2>/dev/null || exit 2
fi

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/terminal-output.sh"
WORKSHOP_SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

resolve_engine() {
    local requested="${1:-}" configured="${AZD_CONTAINER_RUNTIME:-}" value
    for value in "$requested" "$configured"; do
        case "$value" in ''|docker|podman) ;; *) workshop_status_printf '%s\n' '[FAIL] The engine must be docker or podman.' >&2; return 2 ;; esac
    done
    if [[ -n "$requested" && -n "$configured" && "$requested" != "$configured" ]]; then
        workshop_status_printf '%s\n' '[FAIL] The engine argument does not match AZD_CONTAINER_RUNTIME.' >&2
        return 2
    fi
    printf '%s\n' "${requested:-${configured:-docker}}"
}

probe() {
    PROBE_TEXT=''
    PROBE_CODE=0
    if ! command -v "$1" >/dev/null 2>&1; then PROBE_CODE=127; return 0; fi
    PROBE_TEXT=$("$@" 2>&1) || PROBE_CODE=$?
}

check_result() {
    workshop_status_printf '[%s] [%s] %s: %s\n' "$1" "${4:-${CHECK_CONTEXT:-Bash}}" "$2" "$3"
    if [[ "$1" == FAIL ]]; then CHECK_FAILURES=$((CHECK_FAILURES + 1)); fi
}

tool_path() {
    command -v "$1" 2>/dev/null || true
}

initialize_node_environment() {
    local node_path nvm_dir
    node_path=$(tool_path node)
    if [[ -n "$node_path" ]]; then return 0; fi
    if [[ -n "${NVM_DIR:-}" ]]; then nvm_dir="$NVM_DIR"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then nvm_dir="$XDG_CONFIG_HOME/nvm"
    else nvm_dir="$HOME/.nvm"; fi
    [[ -s "$nvm_dir/nvm.sh" ]] || return 0
    export NVM_DIR="$nvm_dir"
    if ! source "$NVM_DIR/nvm.sh" --no-use || [[ $(type -t nvm) != function ]]; then
        check_result WARN nvm "Failed to initialize nvm: $NVM_DIR/nvm.sh"
        return 1
    fi
    if ! nvm use --silent default; then
        check_result WARN nvm 'Could not activate the default Node.js version in nvm. Set the default version with nvm alias default <installed-version>.'
        return 1
    fi
}

check_azure_provider() {
    local provider="$1"
    probe az provider show --namespace "$provider" --query registrationState --output tsv
    if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == Registered ]]; then check_result PASS "$provider" Registered
    else check_result FAIL "$provider" "Could not verify registration (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}. Register it with the installer or resolve the query error."; fi
}

check_azure_identity() {
    local subscription_id subscription_name tenant_id endpoint
    probe az account show --query '[[id,name]]' --output tsv
    if (( PROBE_CODE != 0 )) || [[ -z "$PROBE_TEXT" ]]; then
        check_result WARN azure-subscription 'Could not retrieve the current subscription. Verify the target subscription and tenant manually.'
        return
    fi
    IFS=$'\t' read -r subscription_id subscription_name <<< "$PROBE_TEXT"
    if [[ -z "$subscription_id" || -z "$subscription_name" ]]; then
        check_result WARN azure-subscription 'Could not parse the current subscription ID and name. Verify the target subscription manually.'
        return
    fi
    check_result MANUAL azure-subscription "$subscription_name ($subscription_id)"
    probe az account show --query tenantId --output tsv
    tenant_id="$PROBE_TEXT"
    if (( PROBE_CODE != 0 )) || [[ ! "$tenant_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        check_result WARN azure-tenant 'Could not retrieve the current tenant ID, so the tenant name cannot be verified.'
        return
    fi
    probe az cloud show --query endpoints.resourceManager --output tsv
    if (( PROBE_CODE != 0 )) || [[ ! "$PROBE_TEXT" =~ ^https:// ]]; then
        check_result WARN azure-tenant "Tenant ID: $tenant_id. Could not retrieve the Azure cloud endpoint, so the tenant name cannot be verified."
        return
    fi
    endpoint="${PROBE_TEXT%/}"
    probe az rest --method get --url "$endpoint/tenants?api-version=2022-12-01" --query "value[?tenantId=='$tenant_id'].displayName | [0]" --output tsv --only-show-errors
    if (( PROBE_CODE == 0 )) && [[ -n "$PROBE_TEXT" && "$PROBE_TEXT" != None && "$PROBE_TEXT" != null ]]; then
        check_result MANUAL azure-tenant "$PROBE_TEXT ($tenant_id)"
    else
        check_result WARN azure-tenant "Tenant ID: $tenant_id. Could not retrieve the tenant name. Check permissions, network access, and the Azure portal."
    fi
}

minimum_version() {
    local text="$1" a b c x y z
    [[ "$text" =~ [0-9]+\.[0-9]+\.[0-9]+- ]] && return 1
    [[ "$text" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]] || return 1
    a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}; c=${BASH_REMATCH[3]}
    IFS=. read -r x y z <<< "$2"
    (( 10#$a > 10#$x || (10#$a == 10#$x && 10#$b > 10#$y) || (10#$a == 10#$x && 10#$b == 10#$y && 10#$c >= 10#$z) ))
}

check_container() {
    local engine="$1" format
    probe "$engine" --version
    if (( PROBE_CODE != 0 )); then
        check_result FAIL container-cli "$engine CLI failed (exit code $PROBE_CODE). See docs/java/00-setup.md."
        return
    fi
    check_result PASS container-cli "$engine CLI is available: $PROBE_TEXT (path: $(tool_path "$engine"))"
    if [[ "$engine" == docker ]]; then format='{{.OSType}}'; else format='{{.Host.OS}}'; fi
    probe "$engine" info --format "$format"
    if (( PROBE_CODE != 0 )); then
        check_result FAIL container-engine "Could not connect to $engine. Check the engine status and permissions. The script will not switch engines automatically."
    elif [[ "$PROBE_TEXT" != linux ]]; then
        check_result FAIL container-engine 'Could not verify a Linux container environment.'
    else
        check_result PASS container-engine "$engine CLI is connected to a Linux container engine. This check does not verify where the engine is installed."
    fi
    if [[ "$engine" == docker ]]; then
        probe docker build --help
        if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == *--platform* ]]; then check_result PASS builder-command 'Found the --platform option in Docker CLI help. An actual build has not been tested.'
        else check_result FAIL builder-command 'Could not verify Docker --platform build support.'; fi
        probe docker buildx version
        if (( PROBE_CODE == 0 )); then check_result PASS builder 'Retrieved the Buildx version through the Docker CLI. An actual build has not been tested.'
        else check_result WARN builder 'Could not verify Buildx. Check build support with an actual azd package command.'; fi
    else
        if [[ "$(uname -s)" == Darwin ]]; then
            probe podman machine list
            if (( PROBE_CODE == 0 )); then check_result PASS podman-machine "Podman machine list (verify the selected connection separately): $PROBE_TEXT"
            else check_result WARN podman-machine 'Could not retrieve the Podman machine list. Verify the machine and connection settings manually.'; fi
        fi
        probe podman build --help
        if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == *--platform* ]]; then
            check_result PASS builder 'Found the --platform option in Podman CLI help. An actual build has not been tested. Docker Buildx is not required.'
        else check_result FAIL builder 'Could not verify Podman --platform build support.'; fi
    fi
    check_result MANUAL container-workload 'During the workshop, verify an actual linux/amd64 image build, container port access, and ACR publishing in this shell. The PASS results above do not guarantee that the workload will succeed.'
}

check_java_sdks() {
    local sdk_dir="${SDKMAN_DIR:-$HOME/.sdkman}" candidate output compiler major compiler_major found8=0 found25=0
    if [[ ! -r "$sdk_dir/bin/sdkman-init.sh" ]]; then
        check_result FAIL sdkman 'SDKMAN initialization file not found. See docs/java/00-setup.md.'
        return
    fi
    # SDKMAN 초기화는 격리된 셸에서 수행해 현재 셸의 JAVA_HOME을 바꾸지 않는다.
    probe bash -c 'source "$1/bin/sdkman-init.sh" >/dev/null && sdk version' _ "$sdk_dir"
    if (( PROBE_CODE != 0 )); then
        check_result FAIL sdkman 'SDKMAN initialization or sdk version failed.'
        return
    fi
    check_result PASS sdkman 'Initialized SDKMAN and retrieved its version.'
    for candidate in "$sdk_dir"/candidates/java/*; do
        [[ "${candidate##*/}" != current && -x "$candidate/bin/java" && -x "$candidate/bin/javac" ]] || continue
        output=$("$candidate/bin/java" -version 2>&1) || continue
        [[ "$output" != *-ea* ]] || continue
        major=''
        if [[ "$output" =~ version[[:space:]]+\"1\.8\. ]]; then major=8
        elif [[ "$output" =~ version[[:space:]]+\"([0-9]+)(\.|\") ]]; then major="${BASH_REMATCH[1]}"; fi
        compiler=$("$candidate/bin/javac" -version 2>&1) || continue
        compiler_major=''
        if [[ "$compiler" =~ javac[[:space:]]+1\.8\. ]]; then compiler_major=8
        elif [[ "$compiler" =~ javac[[:space:]]+([0-9]+)(\.|$) ]]; then compiler_major="${BASH_REMATCH[1]}"; fi
        [[ -n "$major" && "$major" == "$compiler_major" && "$compiler" != *-ea* ]] || continue
        case "$major" in
            8) found8=1 ;;
            25) found25=1 ;;
            *) continue ;;
        esac
        check_result PASS "jdk-$major" "Verified java and javac in the SDKMAN candidate ${candidate##*/}."
    done
    (( found8 == 1 )) || check_result FAIL jdk-8 'JDK 8 installed with SDKMAN is required.'
    (( found25 == 1 )) || check_result FAIL jdk-25 'JDK 25 installed with SDKMAN is required.'
}

check_homebrew() {
    probe brew --version
    if (( PROBE_CODE == 0 )); then check_result PASS homebrew "$PROBE_TEXT"
    else check_result FAIL homebrew 'Homebrew is required. Run ./scripts/install-prerequisites.sh --track java.'; fi
}

check_glibc() {
    local version
    probe getconf GNU_LIBC_VERSION
    if (( PROBE_CODE != 0 )) || [[ ! "$PROBE_TEXT" =~ ^glibc[[:space:]]+([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
        check_result FAIL glibc 'Could not determine the glibc version. Modernize CLI requires glibc 2.27 or later. Use a supported glibc-based Linux distribution.'
        return
    fi
    version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0"
    if minimum_version "$version" 2.27.0; then
        check_result PASS glibc "Version $PROBE_TEXT (Modernize CLI minimum: 2.27)"
    else
        check_result FAIL glibc "Modernize CLI requires glibc 2.27 or later. Detected version: $PROBE_TEXT. Do not install glibc separately; use a supported Linux distribution."
    fi
}

check_modernize_tools() {
    probe modernize --version
    if (( PROBE_CODE == 0 )); then check_result PASS modernize "$PROBE_TEXT"
    elif [[ "$(uname -s)" == Linux && -x "$HOME/.local/bin/modernize" && "$PROBE_CODE" == 127 ]]; then
        check_result FAIL modernize '~/.local/bin/modernize is not on PATH. Open a new terminal or reload your shell configuration.'
    else check_result FAIL modernize "Check the Modernize CLI installation or execution status (exit code $PROBE_CODE)."; fi
    probe gh --version
    if (( PROBE_CODE == 0 )) && minimum_version "$PROBE_TEXT" 2.45.0; then
        check_result PASS gh "$PROBE_TEXT"
        probe gh auth status
        if (( PROBE_CODE == 0 )); then check_result PASS gh-auth 'Verified GitHub CLI authentication. Verify Copilot model access separately.'
        else check_result FAIL gh-auth 'Run gh auth login or resolve the authentication error.'; fi
    else check_result FAIL gh 'GitHub CLI (gh) 2.45.0 or later is required.'; fi
}

check_common() {
    local engine="$1" provider path
    probe git --version
    if (( PROBE_CODE == 0 )); then check_result PASS git "$PROBE_TEXT"; else check_result FAIL git 'Git is required.'; fi
    initialize_node_environment || true
    probe node --version
    if (( PROBE_CODE == 0 )) && minimum_version "$PROBE_TEXT" 22.0.0; then check_result PASS node "$PROBE_TEXT (executable: $(tool_path node))"
    elif (( PROBE_CODE == 127 )); then check_result FAIL node 'Node.js was not found on the PATH in this Bash environment. Configure this environment to use Node.js 22 or later.'
    else check_result FAIL node "Could not run Node.js 22 or later in this Bash environment (exit code $PROBE_CODE, output: ${PROBE_TEXT:-none})."; fi
    probe az version --output json
    if (( PROBE_CODE == 0 )); then
        path=$(tool_path az)
        check_result PASS az "Azure CLI is available (executable: $path)."
        probe az extension show --name containerapp --query version --output tsv
        if (( PROBE_CODE == 0 )) && [[ -n "$PROBE_TEXT" ]]; then check_result PASS az-containerapp "Extension version: $PROBE_TEXT"
        else check_result FAIL az-containerapp 'Install the containerapp extension with the installer or resolve the query error.'; fi
        probe az account show --query state --output tsv
        if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == Enabled ]]; then
            check_result PASS az-login 'An active subscription is available.'
            check_azure_identity
            for provider in Microsoft.App Microsoft.OperationalInsights Microsoft.Storage Microsoft.ContainerRegistry Microsoft.ServiceBus Microsoft.DBforPostgreSQL; do
                check_azure_provider "$provider"
            done
        else check_result FAIL az-login 'Run az login and select an active subscription, or resolve the subscription query failure.'; fi
    else check_result FAIL az 'Check the Azure CLI installation or execution status.'; fi
    probe azd version
    if (( PROBE_CODE == 0 )) && minimum_version "$PROBE_TEXT" 1.37.3; then
        check_result PASS azd "$PROBE_TEXT (executable: $(tool_path azd))"
        probe azd auth login --check-status
        if (( PROBE_CODE == 0 )); then check_result PASS azd-login 'Verified azd authentication status.'
        else check_result FAIL azd-login 'Run azd auth login or resolve the authentication error.'; fi
    elif (( PROBE_CODE == 127 )); then check_result FAIL azd 'azd was not found on the PATH in this Bash environment. Configure this environment to use azd 1.37.3 or later.'
    else check_result FAIL azd "Could not run azd 1.37.3 or later in this Bash environment (exit code $PROBE_CODE, output: ${PROBE_TEXT:-none})."; fi
    check_modernize_tools
    check_container "$engine"
    check_result MANUAL copilot-app 'Verify your Copilot app sign-in, license, organization policies, and terminal access.'
    check_result MANUAL azure-access 'Verify that the Azure CLI subscription shown above is the workshop target. Check its region, quota, role assignments, and permission to configure the database Entra administrator.' 'Azure (manual check)'
}

prerequisite_main() {
    local track='' requested='' engine os previous_dynamic="${AZURE_EXTENSION_USE_DYNAMIC_INSTALL-}"
    while (( $# )); do
        case "$1" in
            --track|--container-engine)
                if (( $# < 2 )) || [[ "$2" == --* || -z "$2" ]]; then workshop_status_printf '%s\n' "[FAIL] A value is required for $1." >&2; return 2; fi
                if [[ "$1" == --track ]]; then track="$2"; else requested="$2"; fi
                shift 2 ;;
            --help|-h) printf '%s\n' './scripts/check-prerequisites.sh --track java [--container-engine docker|podman]'; return 0 ;;
            *) workshop_status_printf '[FAIL] Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
    done
    case "$track" in java|dotnet) ;; *) workshop_status_printf '%s\n' '[FAIL] Specify --track java or --track dotnet.' >&2; return 2 ;; esac
    engine=$(resolve_engine "$requested") || return $?
    os=$(uname -s)
    if [[ "$track" == dotnet ]]; then
        workshop_status_printf '%s\n' '[FAIL] For .NET, run ./scripts/check-prerequisites.ps1 -Track dotnet in Windows PowerShell.'
        return 1
    fi
    case "$os" in
        Darwin|Linux) ;;
        *) workshop_status_printf '%s\n' '[FAIL] Run this on macOS or Linux. In Windows PowerShell, run ./scripts/check-prerequisites.ps1 -Track java.'; return 1 ;;
    esac
    CHECK_FAILURES=0
    if [[ "$os" == Darwin ]]; then CHECK_CONTEXT='macOS Bash'
    else CHECK_CONTEXT='Linux Bash'; fi
    printf 'Track: java / engine: %s / calling environment: %s\n' "$engine" "$CHECK_CONTEXT"
    printf '%s\n' 'The results below are based on this Bash environment PATH and the configuration of the tools it invokes.'
    check_result PASS bash "Bash $BASH_VERSION"
    if [[ "$os" == Darwin ]]; then check_homebrew; fi
    if [[ "$os" == Linux ]]; then check_glibc; fi
    export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
    check_common "$engine"
    check_java_sdks
    if [[ -n "$previous_dynamic" ]]; then export AZURE_EXTENSION_USE_DYNAMIC_INSTALL="$previous_dynamic"
    else unset AZURE_EXTENSION_USE_DYNAMIC_INSTALL; fi
    printf 'Required failures: %s. MANUAL items were not checked automatically.\n' "$CHECK_FAILURES"
    if [[ "$engine" == podman && "${AZD_CONTAINER_RUNTIME:-}" != podman ]]; then
        printf 'Before running azd, run export AZD_CONTAINER_RUNTIME=%s in the current shell.\n' "$engine"
    fi
    (( CHECK_FAILURES == 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then prerequisite_main "$@"; exit $?; fi
