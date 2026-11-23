#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./scripts/install-prerequisites.sh.' >&2
    return 2 2>/dev/null || exit 2
fi

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/terminal-output.sh"
INSTALL_SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$INSTALL_SCRIPTS/check-prerequisites.sh"

can_prompt_azure() {
    [[ -t 0 && -t 1 && -z "${CI:-}" ]]
}

confirm_azure_action() {
    local answer
    can_prompt_azure || return 1
    read -r -p "$1 [y/N] " answer || return 1
    [[ "$answer" == y || "$answer" == Y ]]
}

run_azure_action() {
    if ! "$@"; then
        check_result FAIL azure-action "Command failed: $*. See the error above."
        return 1
    fi
}

prepare_azure_account() {
    local subscriptions selected id name valid=0
    can_prompt_azure || return 0
    probe az account show --query state --output tsv
    if (( PROBE_CODE != 0 )) || [[ "$PROBE_TEXT" != Enabled ]]; then
        check_result WARN az-login "Could not verify an active subscription (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}. This may be a permissions or network issue, not just a sign-in issue."
        if confirm_azure_action 'Run az login with the Azure CLI in this shell?'; then
            run_azure_action az login || return 0
        fi
    fi
    if confirm_azure_action 'Retrieve the subscription list and select the workshop subscription?'; then
        probe az account list --query '[].[id,name]' --output tsv
        if (( PROBE_CODE != 0 )) || [[ -z "$PROBE_TEXT" ]]; then
            check_result WARN azure-subscription "Could not retrieve the subscription list: ${PROBE_TEXT:-no output}"
            return 0
        fi
        subscriptions="$PROBE_TEXT"
        printf 'Subscription ID / name:\n%s\n' "$subscriptions"
        read -r -p 'Subscription ID to select (Enter to keep current): ' selected || return 0
        [[ -n "$selected" ]] || return 0
        while IFS=$'\t' read -r id name; do
            [[ "$selected" == "$id" ]] && valid=1
        done <<< "$subscriptions"
        if (( valid )); then run_azure_action az account set --subscription "$selected" || return 0
        else check_result WARN azure-subscription 'The subscription ID is not in the list. The subscription was not changed.'; fi
    fi
}

prepare_containerapp_extension() {
    can_prompt_azure || return 0
    probe az extension show --name containerapp --query version --output tsv
    if (( PROBE_CODE != 0 )) || [[ -z "$PROBE_TEXT" ]]; then
        check_result WARN az-containerapp "Could not retrieve the extension (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}"
        if confirm_azure_action 'Install or update the containerapp extension? Local Azure CLI extension files will be changed.'; then
            run_azure_action az extension add --name containerapp --upgrade || return 0
        fi
    fi
}

prepare_azd_login() {
    can_prompt_azure || return 0
    probe azd auth login --check-status
    if (( PROBE_CODE != 0 )); then
        check_result WARN azd-login "Could not verify authentication (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}"
        if confirm_azure_action 'Run azd auth login in this shell? This is separate from Azure CLI sign-in.'; then
            run_azure_action azd auth login || return 0
        fi
    fi
}

prepare_azure_provider() {
    local provider="$1"
    can_prompt_azure || return 0
    probe az provider show --namespace "$provider" --query registrationState --output tsv
    if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == Registered ]]; then
        check_result PASS "$provider" Registered
        return
    fi
    check_result WARN "$provider" "Registration state (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}"
    if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == NotRegistered || "$PROBE_TEXT" == Unregistered || "$PROBE_TEXT" == Registering ]]; then
        if confirm_azure_action "Register the $provider provider in the current Azure CLI subscription and wait for completion? This changes subscription settings and requires registration permissions."; then
            run_azure_action az provider register --namespace "$provider" --wait || true
            probe az provider show --namespace "$provider" --query registrationState --output tsv
        fi
    fi
    if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == Registered ]]; then check_result PASS "$provider" Registered
    else check_result FAIL "$provider" "Could not verify registration (exit code $PROBE_CODE): ${PROBE_TEXT:-no output}. Check the target subscription and registration permissions."; fi
}

prepare_azure_environment() (
    local provider
    export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no
    CHECK_FAILURES=0
    if [[ "$(uname -s)" == Darwin ]]; then CHECK_CONTEXT='macOS Bash'; else CHECK_CONTEXT='Linux Bash'; fi
    if command -v az >/dev/null 2>&1; then
        prepare_azure_account
        prepare_containerapp_extension
        probe az account show --query state --output tsv
        if (( PROBE_CODE == 0 )) && [[ "$PROBE_TEXT" == Enabled ]]; then
            check_azure_identity
            for provider in Microsoft.App Microsoft.OperationalInsights Microsoft.Storage Microsoft.ContainerRegistry Microsoft.ServiceBus Microsoft.DBforPostgreSQL; do
                prepare_azure_provider "$provider"
            done
        fi
    fi
    if command -v azd >/dev/null 2>&1; then prepare_azd_login; fi
    (( CHECK_FAILURES == 0 ))
)

confirm_install() {
    local answer
    can_prompt_azure || return 1
    printf '%s\n' "$1"
    read -r -p 'Install? [y/N] ' answer || return 1
    [[ "$answer" == y || "$answer" == Y ]]
}

run_remote_installer() {
    local url="$1" privilege="$2" interpreter="$3" temporary directory status
    command -v curl >/dev/null 2>&1 || { workshop_status_printf '%s\n' '[FAIL] curl is required.' >&2; return 1; }
    directory="$PWD/.workshop-installer.$$.$RANDOM"
    (umask 077; mkdir -- "$directory") || return 1
    temporary="$directory/install"
    if ! curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --output "$temporary" "$url"; then
        rm -f -- "$temporary"
        rmdir -- "$directory"
        workshop_status_printf '%s\n' '[FAIL] Could not download the installer script.' >&2
        return 1
    fi
    status=0
    if [[ "$privilege" == sudo ]]; then
        sudo "$interpreter" "$temporary" || status=$?
    else
        "$interpreter" "$temporary" || status=$?
    fi
    rm -f -- "$temporary"
    rmdir -- "$directory"
    return "$status"
}

sdkman_missing_dependencies() {
    local dependency
    for dependency in curl zip unzip tar find sed; do
        command -v "$dependency" >/dev/null 2>&1 || printf '%s\n' "$dependency"
    done
}

prepare_sdkman_dependencies() {
    local os="$1" missing dependency package
    local -a packages=()
    missing=$(sdkman_missing_dependencies)
    if [[ -z "$missing" ]]; then return 0; fi
    workshop_status_printf '[WARN] Commands required to install SDKMAN are missing: %s\n' "${missing//$'\n'/, }"
    if [[ "$os" == Linux ]] && command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        while IFS= read -r dependency; do
            case "$dependency" in
                curl|zip|unzip|tar|sed) package="$dependency" ;;
                find) package=findutils ;;
                *) workshop_status_printf '[FAIL] Unknown SDKMAN prerequisite: %s\n' "$dependency" >&2; return 1 ;;
            esac
            packages+=("$package")
        done <<< "$missing"
        if ! confirm_install "SDKMAN prerequisite packages: Install ${packages[*]} in the current Linux environment. This requires sudo and network access and changes system packages."; then
            workshop_status_printf '%s\n' '[WARN] Skipping SDKMAN prerequisite packages; SDKMAN will not be installed.'
            return 1
        fi
        if ! sudo apt-get update || ! sudo apt-get install -y "${packages[@]}"; then
            workshop_status_printf '%s\n' '[FAIL] Could not install SDKMAN prerequisite packages.' >&2
            return 1
        fi
        hash -r
        missing=$(sdkman_missing_dependencies)
        if [[ -z "$missing" ]]; then return 0; fi
        workshop_status_printf '[FAIL] SDKMAN prerequisite commands are still missing after installation: %s\n' "${missing//$'\n'/, }" >&2
        return 1
    fi
    workshop_status_printf '%s\n' '[FAIL] Install the missing commands manually and try again. See docs/java/00-setup.md.' >&2
    return 1
}

verify_sdkman_installation() {
    local sdk_dir="$1"
    if [[ ! -r "$sdk_dir/bin/sdkman-init.sh" ]]; then
        workshop_status_printf '[FAIL] The installer exited, but the SDKMAN initialization file is missing: %s\n' "$sdk_dir/bin/sdkman-init.sh" >&2
        return 1
    fi
    if ! SDKMAN_DIR="$sdk_dir" bash -c 'source "$SDKMAN_DIR/bin/sdkman-init.sh" && [[ $(type -t sdk) == function ]] && sdk version >/dev/null'; then
        workshop_status_printf '[FAIL] SDKMAN initialization or execution failed: %s\n' "$sdk_dir" >&2
        return 1
    fi
}

nvm_directory() {
    if [[ -n "${NVM_DIR:-}" ]]; then printf '%s\n' "$NVM_DIR"
    elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then printf '%s/nvm\n' "$XDG_CONFIG_HOME"
    else printf '%s/.nvm\n' "$HOME"; fi
}

install_node_with_nvm() {
    local nvm_dir
    nvm_dir=$(nvm_directory)
    if [[ ! -s "$nvm_dir/nvm.sh" ]]; then
        if [[ -e "$nvm_dir" || -L "$nvm_dir" ]]; then
            workshop_status_printf '[FAIL] nvm.sh is missing from the nvm path. The existing path will not be changed: %s\n' "$nvm_dir" >&2
            return 1
        fi
        if ! confirm_install "nvm: Run the official installer in $nvm_dir. Network access is required and shell configuration may change. Source: https://github.com/nvm-sh/nvm"; then return 0; fi
        if ! mkdir -p "$nvm_dir"; then
            workshop_status_printf '[FAIL] Could not create the nvm installation path: %s\n' "$nvm_dir" >&2; return 1
        fi
        if ! NVM_DIR="$nvm_dir" NODE_VERSION='' run_remote_installer 'https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh' user bash; then
            workshop_status_printf '%s\n' '[FAIL] nvm installation failed.' >&2; return 1
        fi
    fi
    export NVM_DIR="$nvm_dir"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]] || ! source "$NVM_DIR/nvm.sh" --no-use || [[ $(type -t nvm) != function ]]; then
        workshop_status_printf '%s\n' '[FAIL] Failed to initialize nvm.' >&2; return 1
    fi
    update_node_with_nvm "${1:-0}"
}

update_node_with_nvm() {
    local update="${1:-1}" current='' latest nvm_dir installed active resolved_dir major=22 node_path live_path
    node_path=$(tool_path node)
    if [[ -n "$node_path" ]]; then
        current=$(node --version) || { workshop_status_printf '%s\n' '[FAIL] Could not determine the Node.js version.' >&2; return 1; }
        if [[ ! "$current" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
            workshop_status_printf '%s\n' '[FAIL] Could not verify the stable Node.js version.' >&2; return 1
        fi
        if (( BASH_REMATCH[1] >= 22 )); then major="${BASH_REMATCH[1]}"; fi
    fi
    nvm_dir=$(nvm_directory)
    if [[ ! -s "$nvm_dir/nvm.sh" ]]; then
        workshop_status_printf '%s\n' '[MANUAL] The existing Node.js installation was not verified as nvm-managed. Update it with its existing installer.'
        return 1
    fi
    export NVM_DIR="$nvm_dir"
    if ! source "$NVM_DIR/nvm.sh" --no-use || [[ $(type -t nvm) != function ]]; then
        workshop_status_printf '%s\n' '[FAIL] Failed to initialize nvm.' >&2; return 1
    fi
    # nvm이 있어도 현재 실행 파일이 다른 관리자 소유라면 덮어쓰지 않는다.
    resolved_dir=$(cd -P -- "$NVM_DIR" && pwd) || return 1
    if [[ -n "$current" ]]; then
        installed=$(nvm which current) || return 1
        active=$(canonical_tool_path "$node_path") || return 1
        installed=$(canonical_tool_path "$installed") || return 1
        if [[ "$active" != "$installed" || "$installed" != "$resolved_dir/versions/node/$current/bin/node" ]]; then
            workshop_status_printf '%s\n' '[MANUAL] Could not verify that the current Node.js installation is managed by nvm. Update it with its existing installer.'
            return 1
        fi
        if (( ! update )); then
            workshop_status_printf '[INFO] Keeping Node.js %s (--update not specified).\n' "$current"
            version_not_older "${current#v}" 22.0.0
            return $?
        fi
    fi
    latest=$(nvm version-remote "$major") || { workshop_status_printf '[FAIL] Could not retrieve the latest Node.js %s version.\n' "$major" >&2; return 1; }
    if [[ ! "$latest" =~ ^v$major\.[0-9]+\.[0-9]+$ ]]; then
        workshop_status_printf '[FAIL] Could not verify a stable Node.js %s identifier.\n' "$major" >&2; return 1
    fi
    if [[ -n "$current" ]] && version_not_older "${current#v}" "${latest#v}"; then
        npm --version || return 1
        workshop_status_printf '[INFO] Keeping Node.js %s (already current; no downgrade).\n' "$current"; return 0
    fi
    installed="$NVM_DIR/versions/node/$latest/bin"
    # nvm install의 자동 default alias 생성은 설치 하위 셸에서만 막는다.
    if [[ $(nvm version "$latest") != "$latest" ]]; then
        if [[ $(type -t nvm_ensure_default_set) != function ]]; then
            workshop_status_printf '%s\n' '[MANUAL] Could not verify how this nvm preserves the default alias. Update manually.'
            return 1
        fi
        if ! confirm_install "Node.js $major: Install $latest with nvm. Existing versions will be preserved."; then
            [[ -n "$current" ]] && version_not_older "${current#v}" 22.0.0
            return $?
        fi
        if ! (
            nvm_ensure_default_set() { return 0; }
            nvm install --no-use "$latest"
        ); then
            workshop_status_printf '%s\n' '[FAIL] Node.js installation failed.' >&2; return 1
        fi
    fi
    if [[ $("$installed/node" --version) != "$latest" ]] || ! PATH="$installed:$PATH" "$installed/npm" --version; then
        workshop_status_printf '%s\n' '[FAIL] Could not verify the installed Node.js or npm executable.' >&2; return 1
    fi
    if ! confirm_install "Activate Node.js $latest: Run nvm use in the script environment. The default alias and existing versions will be preserved; the parent terminal will not be changed."; then
        workshop_status_printf '[INFO] Not activated. Run nvm use %s manually if needed.\n' "$latest"
        [[ -n "$current" ]] && version_not_older "${current#v}" 22.0.0
        return $?
    fi
    live_path=$(tool_path node)
    if [[ "$live_path" != "$node_path" ]] ||
        { [[ -n "$current" ]] && { [[ $(node --version) != "$current" ]] ||
            [[ $(canonical_tool_path "$live_path") != "$active" ]]; }; }; then
        workshop_status_printf '%s\n' '[MANUAL] The active Node.js changed; it will not be activated.' >&2; return 1
    fi
    if ! nvm use "$latest" || [[ $(node --version) != "$latest" ]] ||
        [[ $(canonical_tool_path "$(tool_path node)") != "$resolved_dir/versions/node/$latest/bin/node" ]] ||
        ! npm --version; then
        workshop_status_printf '%s\n' '[FAIL] Could not activate Node.js or verify its execution.' >&2; return 1
    fi
    workshop_status_printf '[PASS] Node.js %s activated (script environment; default alias preserved).\n' "$latest"
    workshop_status_printf '[INFO] The parent terminal is unchanged. To activate in the current terminal, run: export NVM_DIR=%q; source "$NVM_DIR/nvm.sh" --no-use; nvm use %s\n' "$NVM_DIR" "$latest"
}

canonical_tool_path() (
    local path="$1" link count=0
    [[ -e "$path" ]] || return 1
    while [[ -L "$path" ]]; do
        (( count++ < 40 )) || return 1
        link=$(readlink "$path") || return 1
        if [[ "$link" == /* ]]; then path="$link"; else path="$(dirname "$path")/$link"; fi
    done
    cd -P -- "$(dirname "$path")" || return 1
    printf '%s/%s\n' "${PWD%/}" "${path##*/}"
)

version_not_older() {
    local next="$1" previous="$2" i
    local -a a b
    [[ "$next" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$previous" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a a <<< "$next"
    IFS=. read -r -a b <<< "$previous"
    for i in 0 1 2; do
        (( 10#${a[i]} > 10#${b[i]} )) && return 0
        (( 10#${a[i]} < 10#${b[i]} )) && return 1
    done
    return 0
}

azure_tool_version() {
    local text
    if [[ "$1" == az ]]; then
        text=$(az version --query '"azure-cli"' --output tsv) || return 1
        [[ "$text" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
        printf '%s\n' "$text"
    elif [[ "$1" == azd ]]; then
        text=$(azd version) || return 1
        [[ "$text" =~ ^azd[[:space:]]version[[:space:]]([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$) ]] || return 1
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        text=$("$1" --version) || return 1
        [[ "$text" != *-rc* && "$text" != *-preview* && "$text" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

ensure_homebrew() {
    local environment profile brew_path
    if command -v brew >/dev/null 2>&1; then
        brew --version && return 0
        workshop_status_printf '%s\n' '[FAIL] The existing Homebrew executable failed. Verify the installation manually.' >&2
        return 1
    fi
    if ! confirm_install 'Homebrew: Run the official installer. Network access, disk space, and administrator privileges are required; Xcode Command Line Tools may be installed. Source: https://brew.sh'; then
        workshop_status_printf '%s\n' '[FAIL] Homebrew installation was not approved; skipping tools that depend on Homebrew.' >&2; return 1
    fi
    if ! run_remote_installer 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' user /bin/bash; then
        workshop_status_printf '%s\n' '[FAIL] Homebrew installation failed.' >&2; return 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
        if [[ -x /opt/homebrew/bin/brew ]]; then export PATH="/opt/homebrew/bin:$PATH"
        elif [[ -x /usr/local/bin/brew ]]; then export PATH="/usr/local/bin:$PATH"; fi
    fi
    if ! brew --version; then workshop_status_printf '%s\n' '[FAIL] Could not verify that Homebrew runs.' >&2; return 1; fi
    environment=$(brew shellenv) && eval "$environment" || {
        workshop_status_printf '%s\n' '[FAIL] Could not apply Homebrew shellenv.' >&2; return 1;
    }
    brew_path=$(command -v brew)
    case "${SHELL##*/}" in zsh) profile='~/.zprofile' ;; *) profile='~/.bash_profile' ;; esac
    workshop_status_printf '[MANUAL] Add this command to %s: eval "$(%s shellenv)"\n' "$profile" "$brew_path"
}

microsoft_apt_candidate() {
    local policy origin="${2:-packages.microsoft.com}"
    policy=$(LC_ALL=C apt-cache policy "$1") || return 2
    printf '%s\n' "$policy" | awk -v origin="$origin" '
        /Candidate:/ { candidate=$2 }
        /^[[:space:]]*(\*\*\*[[:space:]]*)?[^[:space:]]+[[:space:]]+[0-9]+$/ {
            version=$1 == "***" ? $2 : $1
        }
        version == candidate && index($2, "https://" origin "/") == 1 { found=1 }
        END { if(found) print candidate; else exit 1 }'
}

linux_azd_target() {
    case "$(uname -m)" in
        x86_64) printf '/opt/microsoft/azd/azd-linux-amd64\n' ;;
        aarch64|arm64) printf '/opt/microsoft/azd/azd-linux-arm64\n' ;;
        *) workshop_status_printf '%s\n' '[FAIL] azd: Unsupported CPU architecture.' >&2; return 1 ;;
    esac
}

linux_azd_link() { printf '/usr/local/bin/azd\n'; }

azd_file_hash() {
    local result
    result=$(sha256sum -- "$1") || return 1
    [[ "$result" =~ ^([a-f0-9]{64})[[:space:]] ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

azd_package_owned() {
    local path status
    for path in "$@"; do
        if command -v dpkg-query >/dev/null 2>&1; then
            dpkg-query -S "$path" >/dev/null 2>&1 && return 0
            status=$?
            (( status == 1 )) || return 2
        fi
        if command -v rpm >/dev/null 2>&1; then
            rpm -qf "$path" >/dev/null 2>&1 && return 0
            status=$?
            (( status == 1 )) || return 2
        fi
    done
    return 1
}

install_linux_azd() (
    local path="${1:-}" target link before='' digest='' after live
    local state="${XDG_STATE_HOME:-$HOME/.local/state}/app-modernisation-workshop"
    local record temporary owner_status ancestor line
    local -a saved=()
    if ! command -v sha256sum >/dev/null 2>&1; then
        workshop_status_printf '%s\n' '[FAIL] azd: sha256sum is required to verify the installation record.' >&2; return 1
    fi
    record="$state/azd-script-install"
    target=$(linux_azd_target) || return 1
    link=$(linux_azd_link) || return 1
    for ancestor in "${target%/*}" "${link%/*}" "$state"; do
        while [[ ! -e "$ancestor" && ! -L "$ancestor" && "$ancestor" != / ]]; do ancestor=$(dirname -- "$ancestor"); done
        if [[ "$ancestor" != /* || ! -d "$ancestor" ]] ||
            { [[ "$ancestor" != / ]] && [[ "$(canonical_tool_path "$ancestor")" != "$ancestor" ]]; }; then
            workshop_status_printf '[FAIL] azd: Installation/record path is not a normal absolute path: %s\n' "$ancestor" >&2; return 1
        fi
    done
    if [[ -L "$state" || -L "$record" || ( -e "$state" && ! -d "$state" ) ]]; then
        workshop_status_printf '%s\n' '[FAIL] azd: The managed record path is not a regular directory or file.' >&2; return 1
    fi
    if azd_package_owned "$link" "$target" "${path:-$link}"; then
        workshop_status_printf '%s\n' '[MANUAL] azd: Installations owned by a package manager will not be overwritten by the official script.'
        return 0
    else
        owner_status=$?
        if (( owner_status != 1 )); then
            workshop_status_printf '%s\n' '[FAIL] azd: Could not query package ownership.' >&2; return 1
        fi
    fi
    if [[ -n "$path" ]]; then
        if [[ "$path" != "$link" || ! -L "$link" || ! -f "$target" || ! -x "$target" || -L "$target" ||
            "$(canonical_tool_path "$target")" != "$target" ||
            "$(canonical_tool_path "$link")" != "$target" ]]; then
            workshop_status_printf '[MANUAL] azd: An installation outside the default path used by the official script will not be overwritten: %s\n' "$path"
            return 0
        fi
        before=$(azure_tool_version azd) && digest=$(azd_file_hash "$target") || {
            workshop_status_printf '%s\n' '[FAIL] azd: Could not verify the existing version/hash.' >&2; return 1;
        }
        if [[ -e "$record" ]]; then
            [[ -f "$record" && -r "$record" ]] || {
                workshop_status_printf '%s\n' '[FAIL] azd: Could not read the managed record.' >&2; return 1;
            }
            while IFS= read -r line || [[ -n "$line" ]]; do saved+=("$line"); done < "$record"
            if [[ "${#saved[@]}" != 4 || "${saved[0]}" != official-script ||
                "${saved[1]}" != "$target" || "${saved[2]}" != "$before" || "${saved[3]}" != "$digest" ]]; then
                workshop_status_printf '%s\n' '[FAIL] azd: The installed file does not match the managed record. It will not be changed automatically.' >&2; return 1
            fi
        else
            if ! confirm_install "azd $before ($path -> $target): The installation source is unverified. Approve taking over and updating this installation with the official Microsoft script?"; then return 0; fi
        fi
    elif [[ -e "$link" || -L "$link" || -e "${target%/*}" || -L "${target%/*}" || -e "$record" ]]; then
        workshop_status_printf '%s\n' '[MANUAL] azd: An existing installation path or managed record remains. Nothing will be overwritten.'
        return 0
    fi
    if ! confirm_install "azd ${before:-not installed}: Install/update with the official Microsoft script. Network access and sudo may be required. Source: https://aka.ms/install-azd.sh"; then return 0; fi
    live=$(tool_path azd)
    if [[ "$live" != "$path" ]] || { [[ -n "$path" ]] &&
        { [[ "$(canonical_tool_path "$link")" != "$target" ]] ||
          [[ "$(azd_file_hash "$target")" != "$digest" ]]; }; }; then
        workshop_status_printf '%s\n' '[FAIL] azd: The executable path/file changed while approval was pending.' >&2; return 1
    fi
    if [[ -z "$path" && ( -e "$link" || -L "$link" || -e "${target%/*}" || -L "${target%/*}" || -e "$record" ) ]]; then
        workshop_status_printf '%s\n' '[FAIL] azd: An installation path/managed record was created while approval was pending.' >&2; return 1
    fi
    if azd_package_owned "$link" "$target"; then
        workshop_status_printf '%s\n' '[FAIL] azd: Package ownership changed while approval was pending.' >&2; return 1
    else
        owner_status=$?
        if (( owner_status != 1 )); then
            workshop_status_printf '%s\n' '[FAIL] azd: Could not recheck package ownership.' >&2; return 1
        fi
    fi
    temporary="$state/.azd-script-install.$$.$RANDOM"
    if ! (umask 077; mkdir -p -- "$state" && set -C && : > "$temporary"); then
        workshop_status_printf '%s\n' '[FAIL] azd: Could not prepare the managed record.' >&2; return 1
    fi
    trap "rm -f -- $(printf '%q' "$temporary")" EXIT
    if ! run_remote_installer 'https://aka.ms/install-azd.sh' user bash; then
        workshop_status_printf '%s\n' '[FAIL] azd installation/update with the official script failed.' >&2; return 1
    fi
    hash -r
    if [[ "$(tool_path azd)" != "$link" || ! -L "$link" || ! -f "$target" || ! -x "$target" || -L "$target" ||
        "$(canonical_tool_path "$link")" != "$target" ]] ||
        ! after=$(azure_tool_version azd) || { [[ -n "$before" ]] && ! version_not_older "$after" "$before"; } ||
        ! digest=$(azd_file_hash "$target"); then
        workshop_status_printf '%s\n' '[FAIL] azd: Post-install path/version/hash verification failed. The managed record will not be updated.' >&2; return 1
    fi
    if ! printf 'official-script\n%s\n%s\n%s\n' "$target" "$after" "$digest" > "$temporary" ||
        ! mv -f -- "$temporary" "$record"; then
        workshop_status_printf '%s\n' '[FAIL] azd: Could not save the managed record.' >&2; return 1
    fi
    workshop_status_printf '[PASS] azd: Verified installation/update with the official script (%s -> %s).\n' "${before:-not installed}" "$after"
)

update_azure_tool() {
    local os="$1" tool="$2" path="$3" package prefix managed='' before after candidate installed outdated origin=packages.microsoft.com
    case "$tool" in az) package=azure-cli ;; azd) package=azd ;; gh) package=gh; origin=cli.github.com ;; esac
    if [[ "$os" == Darwin ]] && command -v brew >/dev/null 2>&1; then
        [[ "$tool" != azd ]] || package=azure/azd/azd
        if prefix=$(brew --prefix "$package") && brew list --versions "$package" >/dev/null 2>&1 &&
            [[ -x "$prefix/bin/$tool" ]] &&
            [[ "$(canonical_tool_path "$path")" == "$(canonical_tool_path "$prefix/bin/$tool")" ]]; then managed=brew; fi
    elif [[ "$os" == Linux ]] && command -v dpkg-query >/dev/null 2>&1 &&
        command -v apt-cache >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        # Verify both the selected executable's owner and the official update source.
        if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == 'install ok installed' ]] &&
            { [[ "$(dpkg-query -S "$path" 2>/dev/null)" == "$package: $path" ]] ||
              [[ "$(dpkg-query -S "$(canonical_tool_path "$path")" 2>/dev/null)" == "$package: $(canonical_tool_path "$path")" ]]; }; then
            if candidate=$(microsoft_apt_candidate "$package" "$origin"); then
                installed=$(dpkg-query -W -f='${Version}' "$package") || return 1
                if ! dpkg --compare-versions "$candidate" ge "$installed"; then
                    workshop_status_printf '[FAIL] %s: The APT candidate is older than the current version. No changes were made.\n' "$tool" >&2; return 1
                fi
                managed=apt
            else
                case $? in
                    1) ;;
                    *) workshop_status_printf '[FAIL] %s: Could not query the APT update source.\n' "$tool" >&2; return 1 ;;
                esac
            fi
        fi
    fi
    if [[ -z "$managed" && "$os" == Linux && "$tool" == azd ]]; then
        install_linux_azd "$path"
        return $?
    fi
    if [[ -z "$managed" ]]; then
        workshop_status_printf '[MANUAL] %s: Could not verify the Homebrew/official APT repository source for this executable. It will not be overwritten. See docs/java/08-troubleshooting.md.\n' "$tool"
        return 0
    fi
    if ! before=$(azure_tool_version "$tool"); then workshop_status_printf '[FAIL] Could not run %s to verify its version.\n' "$tool" >&2; return 1; fi
    if [[ "$managed" == brew ]]; then
        if ! outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet "$package"); then
            workshop_status_printf '[FAIL] Could not query Homebrew updates for %s.\n' "$tool" >&2; return 1
        fi
        if [[ -z "$outdated" ]]; then
            workshop_status_printf '[INFO] Keeping %s %s (current in available Homebrew metadata).\n' "$tool" "$before"; return 0
        fi
    elif dpkg --compare-versions "$candidate" eq "$installed"; then
        workshop_status_printf '[INFO] Keeping %s %s (current in available APT metadata).\n' "$tool" "$before"; return 0
    fi
    if ! confirm_install "$tool $before: Update the verified $managed package $package and required dependencies. Network access and administrator privileges may be required. This will not upgrade the entire OS."; then return 0; fi
    if [[ "$managed" == brew ]]; then
        if ! brew upgrade "$package"; then workshop_status_printf '[FAIL] %s update failed.\n' "$tool" >&2; return 1; fi
    else
        if ! sudo apt-get update; then
            workshop_status_printf '[FAIL] Could not refresh the %s update list.\n' "$tool" >&2; return 1
        fi
        # Recheck the candidate source and downgrade status after refreshing, then request only that version.
        if ! candidate=$(microsoft_apt_candidate "$package" "$origin") ||
            ! dpkg --compare-versions "$candidate" ge "$installed"; then
            workshop_status_printf '[FAIL] Could not verify a safe official APT candidate for %s after refreshing.\n' "$tool" >&2; return 1
        fi
        if ! sudo apt-get install --only-upgrade --no-remove -y "$package=$candidate"; then
            workshop_status_printf '[FAIL] %s update failed.\n' "$tool" >&2; return 1
        fi
    fi
    hash -r
    if ! after=$(azure_tool_version "$tool") || ! version_not_older "$after" "$before"; then
        workshop_status_printf '[FAIL] Could not verify the %s version/executable after updating.\n' "$tool" >&2; return 1
    fi
    workshop_status_printf '[PASS] %s: %s → %s (kept if already current).\n' "$tool" "$before" "$after"
}

latest_temurin_identifier() {
    local major="$1"
    awk -F '|' -v major="$major" '
        function newer(a,b, av,bv,ab,bb,an,bn,i,n) {
            split(a,ab,/\+/); split(b,bb,/\+/)
            an=split(ab[1],av,/\./); bn=split(bb[1],bv,/\./); n=an>bn?an:bn
            for(i=1;i<=n;i++) { if(av[i]+0>bv[i]+0) return 1; if(av[i]+0<bv[i]+0) return 0 }
            an=split(ab[2],av,/\./); bn=split(bb[2],bv,/\./); n=an>bn?an:bn
            for(i=1;i<=n;i++) { if(av[i]+0>bv[i]+0) return 1; if(av[i]+0<bv[i]+0) return 0 }
            return 0
        }
        { id=$NF; gsub(/\033\[[0-9;]*m/,"",id); gsub(/^[ \t]+|[ \t\r]+$/,"",id)
          if(id ~ ("^" major "\\.[0-9]+(\\.[0-9]+)*(\\+[0-9]+(\\.[0-9]+)*)?-tem$")) {
              version=id; sub(/-tem$/,"",version)
              if(best=="" || newer(version,best)) { best=version; selected=id }
          }
        }
        END { if(selected!="") print selected }'
}

jdk_matches_major() {
    local candidate="$1" major="$2" runtime compiler
    [[ -x "$candidate/bin/java" && -x "$candidate/bin/javac" ]] || return 1
    runtime=$("$candidate/bin/java" -version 2>&1) || return 1
    compiler=$("$candidate/bin/javac" -version 2>&1) || return 1
    [[ "$runtime" != *-ea* && "$compiler" != *-ea* ]] || return 1
    if [[ "$major" == 8 ]]; then
        [[ "$runtime" =~ version[[:space:]]+\"1\.8\. && "$compiler" =~ javac[[:space:]]+1\.8\. ]]
    else
        [[ "$runtime" =~ version[[:space:]]+\"$major(\.|\") && "$compiler" =~ javac[[:space:]]+$major(\.|$) ]]
    fi
}

jdk_matches_identifier() {
    local candidate="$1" identifier="$2" major="${2%%.*}" expected actual runtime compiler
    jdk_matches_major "$candidate" "$major" || return 1
    expected="${identifier%-tem}"
    expected="${expected%%+*}"
    if [[ "$major" == 8 ]]; then
        expected="${expected#8.0.}"
        expected="1.8.0_${expected%%.*}"
    else
        while [[ "$expected" == *.0 ]]; do expected="${expected%.0}"; done
    fi
    runtime=$("$candidate/bin/java" -version 2>&1) || return 1
    compiler=$("$candidate/bin/javac" -version 2>&1) || return 1
    [[ "$runtime" =~ version[[:space:]]+\"([^\"]+)\" ]] || return 1
    actual="${BASH_REMATCH[1]}"
    actual="${actual%%+*}"
    if [[ "$major" != 8 ]]; then while [[ "$actual" == *.0 ]]; do actual="${actual%.0}"; done; fi
    [[ "$actual" == "$expected" ]] || return 1
    [[ "$compiler" =~ javac[[:space:]]+([^[:space:]]+) ]] || return 1
    actual="${BASH_REMATCH[1]}"
    actual="${actual%%+*}"
    if [[ "$major" != 8 ]]; then while [[ "$actual" == *.0 ]]; do actual="${actual%.0}"; done; fi
    [[ "$actual" == "$expected" ]]
}

install_java_sdks() (
    export SDKMAN_DIR="$1"
    local update="${2:-0}" major candidate identifier listing failed=0 found USE
    if ! source "$SDKMAN_DIR/bin/sdkman-init.sh"; then
        workshop_status_printf '%s\n' '[FAIL] Failed to initialize SDKMAN to install JDKs.' >&2; return 1
    fi
    # SDKMAN 설치 함수가 참조하는 응답을 지정해 기존 기본 JDK를 유지한다.
    sdkman_auto_answer=false
    sdkman_colour_enable=false
    for major in 8 25; do
        found=0
        for candidate in "$SDKMAN_DIR"/candidates/java/*; do
            [[ "${candidate##*/}" != current ]] || continue
            if jdk_matches_major "$candidate" "$major"; then found=1; break; fi
        done
        if (( found && ! update )); then workshop_status_printf '[INFO] JDK %s: Using existing SDKMAN installation (%s).\n' "$major" "${candidate##*/}"; continue; fi
        if (( ! update )) && ! confirm_install "JDK $major: Select and install a stable Temurin JDK available for this environment from the SDKMAN list. Network access and disk space are required. The existing default JDK will be preserved."; then continue; fi
        if ! listing=$(PAGER=cat sdk list java); then
            workshop_status_printf '[FAIL] Could not retrieve the JDK %s installation list.\n' "$major" >&2; failed=1; continue
        fi
        if (( update )); then
            identifier=$(printf '%s\n' "$listing" | latest_temurin_identifier "$major")
        else
            identifier=$(printf '%s\n' "$listing" | awk -F '|' -v major="$major" '
            { id=$NF; gsub(/\033\[[0-9;]*m/, "", id); gsub(/^[ \t]+|[ \t\r]+$/, "", id)
              if (id ~ ("^" major "\\.[0-9]+(\\.[0-9]+)*(\\+[0-9]+(\\.[0-9]+)*)?-tem$")) { print id; exit } }')
        fi
        if [[ -z "$identifier" ]]; then
            workshop_status_printf '[FAIL] No stable Temurin JDK %s is available in the SDKMAN list for this environment. Check other distributions with sdk list java.\n' "$major" >&2
            failed=1; continue
        fi
        if (( update )); then
            candidate="$SDKMAN_DIR/candidates/java/$identifier"
            if [[ -e "$candidate" || -L "$candidate" ]]; then
                if jdk_matches_identifier "$candidate" "$identifier"; then
                    workshop_status_printf '[INFO] JDK %s: The latest %s is already installed.\n' "$major" "$identifier"
                else
                    workshop_status_printf '[FAIL] Could not verify the existing JDK %s executable. It will not be overwritten.\n' "$identifier" >&2; failed=1
                fi
                continue
            fi
            if ! confirm_install "JDK $major: Install the latest stable Temurin $identifier alongside existing versions. Network access and disk space are required; existing versions and the default JDK will be preserved."; then continue; fi
        fi
        USE=n
        if ! sdk install java "$identifier" <<< n || ! jdk_matches_major "$SDKMAN_DIR/candidates/java/$identifier" "$major"; then
            workshop_status_printf '[FAIL] Could not install or verify JDK %s (%s).\n' "$major" "$identifier" >&2; failed=1
        elif (( update )) && ! jdk_matches_identifier "$SDKMAN_DIR/candidates/java/$identifier" "$identifier"; then
            workshop_status_printf '[FAIL] The actual JDK %s version does not match the requested %s.\n' "$major" "$identifier" >&2; failed=1
        fi
    done
    workshop_status_printf '[INFO] To use SDKMAN in the current terminal, run: source %q\n' "$SDKMAN_DIR/bin/sdkman-init.sh"
    return "$failed"
)

linux_install_supported() {
    if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then return 0; fi
    workshop_status_printf '[WARN] Automatic installation of %s requires apt-get and sudo. Official manual installation instructions: %s\n' "$1" "$2"
    return 1
}

install_linux_gh() (
    local directory architecture
    if ! confirm_install 'GitHub CLI (gh): Add the official cli.github.com APT repository and keyring, then install gh. This requires sudo and network access and changes system packages. Source: https://github.com/cli/cli/blob/trunk/docs/install_linux.md'; then return 0; fi
    architecture=$(dpkg --print-architecture) || return 1
    case "$architecture" in amd64|arm64|armhf|i386) ;; *) workshop_status_printf '%s\n' '[FAIL] gh: Could not verify a supported APT architecture.' >&2; return 1 ;; esac
    directory="$PWD/.workshop-gh.$$.$RANDOM"
    (umask 077; mkdir -- "$directory") || return 1
    trap "rm -rf -- $(printf '%q' "$directory")" EXIT
    if ! curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --output "$directory/keyring.gpg" 'https://cli.github.com/packages/githubcli-archive-keyring.gpg' ||
        ! sudo install -d -m 0755 /etc/apt/keyrings ||
        ! sudo install -m 0644 "$directory/keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg; then
        workshop_status_printf '%s\n' '[FAIL] Could not prepare the official gh APT keyring.' >&2; return 1
    fi
    if ! printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$architecture" |
        sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null ||
        ! sudo apt-get update || ! sudo apt-get install -y gh; then
        workshop_status_printf '%s\n' '[FAIL] Official APT installation of gh failed.' >&2; return 1
    fi
    hash -r
    local version
    version=$(gh --version) && minimum_version "$version" 2.45.0 || {
        workshop_status_printf '%s\n' '[FAIL] Could not run gh 2.45.0 or later after installation.' >&2; return 1;
    }
)

install_modernize() {
    local os="$1" update="$2" path="${3:-}" before='' after cask_root outdated release latest
    if [[ -n "$path" ]]; then
        if [[ "$os" == Darwin ]]; then
            cask_root=$(brew --caskroom microsoft/modernize/modernize) &&
                brew list --cask --versions microsoft/modernize/modernize >/dev/null 2>&1 || {
                    workshop_status_printf '%s\n' '[MANUAL] Could not verify the Modernize CLI Homebrew source. Update it with its existing installer.'; return 0;
                }
            case "$(canonical_tool_path "$path")" in "$cask_root"/*) ;; *)
                workshop_status_printf '%s\n' '[MANUAL] The Modernize CLI executable path does not match the Homebrew cask. It will not be overwritten.'; return 0 ;; esac
        else
            if [[ "$path" != "$HOME/.local/bin/modernize" ]]; then
                workshop_status_printf '%s\n' '[MANUAL] Modernize CLI is outside the official installation path. Update it with its existing installer.'; return 0
            fi
        fi
        before=$(azure_tool_version modernize) || return 1
        if [[ "$os" == Darwin ]]; then
            if ! outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --cask --greedy --quiet microsoft/modernize/modernize); then
                workshop_status_printf '%s\n' '[FAIL] Could not query Homebrew updates for Modernize CLI.' >&2; return 1
            fi
            if [[ -z "$outdated" ]]; then
                workshop_status_printf '[INFO] Keeping Modernize CLI %s (current in available Homebrew metadata).\n' "$before"; return 0
            fi
        else
            if ! release=$(curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --max-time 30 'https://api.github.com/repos/microsoft/modernize-cli/releases/latest'); then
                workshop_status_printf '%s\n' '[FAIL] Could not query the latest Modernize CLI release.' >&2; return 1
            fi
            latest=$(printf '%s\n' "$release" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p')
            if ! version_not_older "$latest" 0.0.0; then
                workshop_status_printf '%s\n' '[FAIL] Could not verify a stable Modernize CLI release version.' >&2; return 1
            fi
            if version_not_older "$before" "$latest"; then
                workshop_status_printf '[INFO] Keeping Modernize CLI %s (already current; no downgrade).\n' "$before"; return 0
            fi
        fi
    fi
    if [[ "$os" == Darwin ]]; then
        if ! confirm_install 'Modernize CLI: Add the Homebrew tap microsoft/modernize and install/update the microsoft/modernize/modernize cask. Network access and disk space are required. Source: https://github.com/microsoft/modernize-cli'; then return 0; fi
        if ! brew tap microsoft/modernize https://github.com/microsoft/modernize-cli; then return 1; fi
        if [[ -n "$path" && "$update" == 1 ]]; then
            brew upgrade --cask microsoft/modernize/modernize || return 1
        else
            brew install --cask microsoft/modernize/modernize || return 1
        fi
    else
        if ! confirm_install 'Modernize CLI: Run the official install.sh with sh to install/update in ~/.local/share/modernize and ~/.local/bin. sudo is not used; glibc 2.27 or later is required. Network access and disk space are used, and the installer adds PATH to shell configuration such as ~/.bashrc. Source: https://github.com/microsoft/modernize-cli'; then return 0; fi
        run_remote_installer 'https://raw.githubusercontent.com/microsoft/modernize-cli/main/scripts/install.sh' user sh || return 1
        export PATH="$HOME/.local/bin:$PATH"
    fi
    hash -r
    if ! after=$(azure_tool_version modernize) ||
        { [[ -n "$before" ]] && ! version_not_older "$after" "$before"; }; then
        workshop_status_printf '%s\n' '[FAIL] Could not verify the Modernize CLI version after installation.' >&2; return 1
    fi
    workshop_status_printf '[PASS] Modernize CLI %s\n' "$after"
}

install_missing_tools() {
    local os="$1" update="${2:-0}" tool path sdk_dir="${SDKMAN_DIR:-$HOME/.sdkman}" failed=0 brew_ready=1 interpreter
    if [[ "$os" == Darwin ]] && ! ensure_homebrew; then failed=1; brew_ready=0; fi
    for tool in node az azd gh modernize sdkman; do
        case "$os:$tool" in
            Darwin:az|Darwin:azd|Darwin:gh|Darwin:modernize)
                if (( ! brew_ready )); then workshop_status_printf '[WARN] %s: Skipping because Homebrew is unavailable.\n' "$tool"; continue; fi ;;
        esac
        if [[ "$tool" == sdkman ]]; then
            if [[ -e "$sdk_dir" || -L "$sdk_dir" ]]; then
                if [[ ! -r "$sdk_dir/bin/sdkman-init.sh" ]]; then
                    workshop_status_printf '[FAIL] The SDKMAN path already exists, but its initialization file is missing: %s. Check its contents. It will not be changed automatically.\n' "$sdk_dir" >&2
                    failed=1
                elif ! verify_sdkman_installation "$sdk_dir"; then
                    workshop_status_printf '[WARN] The existing SDKMAN path will not be changed automatically. Check its contents: %s\n' "$sdk_dir" >&2
                    failed=1
                else
                    install_java_sdks "$sdk_dir" "$update" || failed=1
                fi
                continue
            fi
        else
            path=$(tool_path "$tool")
            if [[ -n "$path" ]]; then
                if (( update )); then
                    case "$os:$tool" in
                        Linux:az|Linux:azd|Linux:gh|Linux:modernize)
                            linux_install_supported "$tool" 'docs/java/00-setup.md' || continue ;;
                    esac
                    case "$tool" in
                        node) update_node_with_nvm "$update" || failed=1 ;;
                        az|azd|gh) update_azure_tool "$os" "$tool" "$path" || failed=1 ;;
                        modernize) install_modernize "$os" "$update" "$path" || failed=1 ;;
                    esac
                    continue
                fi
                workshop_status_printf '[INFO] %s: Found on PATH (%s). It will not be installed or updated.\n' "$tool" "$path"
                continue
            fi
        fi
        case "$os:$tool" in
            Linux:node|Darwin:node)
                install_node_with_nvm "$update" || failed=1 ;;
            Linux:az)
                linux_install_supported az 'https://learn.microsoft.com/cli/azure/install-azure-cli-linux' || continue
                if confirm_install 'Azure CLI: Run the official Microsoft installer in the current Linux environment. This requires sudo and network access and changes APT repositories and system packages. Source: https://aka.ms/InstallAzureCLIDeb'; then
                    if ! run_remote_installer 'https://aka.ms/InstallAzureCLIDeb' sudo bash; then workshop_status_printf '%s\n' '[FAIL] Azure CLI installation failed.' >&2; failed=1; fi
                fi ;;
            Linux:azd)
                linux_install_supported azd 'https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd' || continue
                install_linux_azd || failed=1 ;;
            Linux:gh)
                linux_install_supported gh 'https://github.com/cli/cli/blob/trunk/docs/install_linux.md' || continue
                install_linux_gh || failed=1 ;;
            Linux:modernize)
                linux_install_supported modernize 'https://github.com/microsoft/modernize-cli' || continue
                install_modernize "$os" "$update" || failed=1 ;;
            Darwin:modernize)
                install_modernize "$os" "$update" || failed=1 ;;
            Darwin:az|Darwin:azd|Darwin:gh)
                case "$tool" in
                    az) set -- azure-cli ;;
                    azd) set -- azure/azd/azd ;;
                    gh) set -- gh ;;
                esac
                if confirm_install "$tool: Install the Homebrew package $1 on macOS. Network access is required, and Homebrew repositories and packages may change."; then
                    if ! brew install "$1"; then workshop_status_printf '[FAIL] %s installation failed.\n' "$tool" >&2; failed=1; fi
                fi ;;
            *:sdkman)
                if [[ "$os" == Darwin ]]; then interpreter=zsh; else interpreter=bash; fi
                if confirm_install "SDKMAN: Run the official installer for the current user in $sdk_dir. Network access is required and shell configuration files may change. Each JDK version requires separate approval. Source: https://get.sdkman.io"; then
                    if ! prepare_sdkman_dependencies "$os"; then
                        failed=1
                    elif ! SDKMAN_DIR="$sdk_dir" run_remote_installer 'https://get.sdkman.io' user "$interpreter"; then
                        workshop_status_printf '%s\n' '[FAIL] SDKMAN installation failed. Check the error above and the existing installation path.' >&2; failed=1
                    elif ! verify_sdkman_installation "$sdk_dir"; then
                        failed=1
                    else
                        install_java_sdks "$sdk_dir" "$update" || failed=1
                    fi
                fi ;;
        esac
    done
    return "$failed"
}

install_prerequisite_main() {
    local track='' requested='' engine os result=0 update=0
    while (( $# )); do
        case "$1" in
            --track|--container-engine)
                if (( $# < 2 )) || [[ -z "$2" || "$2" == --* ]]; then workshop_status_printf '[FAIL] A value is required for %s.\n' "$1" >&2; return 2; fi
                if [[ "$1" == --track ]]; then track="$2"; else requested="$2"; fi
                shift 2 ;;
            --update) update=1; shift ;;
            --help|-h) printf '%s\n' './scripts/install-prerequisites.sh --track java [--container-engine docker|podman] [--update]'; return 0 ;;
            *) workshop_status_printf '[FAIL] Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
    done
    if [[ "$track" == dotnet ]]; then
        workshop_status_printf '%s\n' '[FAIL] For .NET, run ./scripts/install-prerequisites.ps1 -Track dotnet in Windows PowerShell.' >&2; return 1
    fi
    [[ "$track" == java ]] || { workshop_status_printf '%s\n' '[FAIL] Specify --track java.' >&2; return 2; }
    engine=$(resolve_engine "$requested") || return $?
    os=$(uname -s)
    case "$os" in
        Darwin|Linux) ;;
        *) workshop_status_printf '%s\n' '[FAIL] Run this on macOS or Linux. In Windows PowerShell, run ./scripts/install-prerequisites.ps1 -Track java.' >&2; return 1 ;;
    esac
    if [[ ! -t 0 || ! -t 1 || -n "${CI:-}" ]]; then
        workshop_status_printf '%s\n' '[FAIL] Installation is available only in an interactive terminal. Nothing is installed in a non-interactive environment.' >&2
        return 1
    fi
    if (( update )); then
        printf '%s\n' 'Update mode: Changes are made only after verifying each tool source and receiving separate approval. Existing versions and default runtimes are preserved; Node.js activation requires separate approval.'
    else
        printf 'Installation target: %s. Tools already on PATH will not be changed.\n' "$os"
    fi
    install_missing_tools "$os" "$update" || result=1
    if (( result != 0 )); then
        workshop_status_printf '%s\n' '[FAIL] Skipping Azure preparation and follow-up checks because tool installation/update failed.'
        return 1
    fi
    hash -r
    prepare_azure_environment || result=1
    workshop_status_printf '%s\n' '[INFO] Running read-only prerequisite checks from ./scripts/check-prerequisites.sh. Verify MANUAL items yourself.'
    prerequisite_main --track java --container-engine "$engine" || result=1
    return "$result"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then install_prerequisite_main "$@"; exit $?; fi
