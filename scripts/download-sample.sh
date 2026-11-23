#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./scripts/download-sample.sh.' >&2
    return 2 2>/dev/null || exit 2
fi

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/terminal-output.sh"
DOWNLOAD_SCRIPTS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

sample_definition() {
    case "$1" in
        java)
            SAMPLE_REPOSITORY=https://github.com/Azure-Samples/java-migration-copilot-samples.git
            SAMPLE_COMMIT=317d3bbfd61fb1e402bea61f90e385bec12f2070
            SAMPLE_SUBDIRECTORY=asset-manager ;;
        dotnet)
            SAMPLE_REPOSITORY=https://github.com/Azure-Samples/dotnet-migration-copilot-samples.git
            SAMPLE_COMMIT=7c1bf47b7e2627fe5a1c764716638815d35e0282
            SAMPLE_SUBDIRECTORY=ContosoUniversity ;;
        *) workshop_status_printf '%s\n' '[FAIL] Unknown track.' >&2; return 2 ;;
    esac
}

safe_destination() {
    local path="$1" workshop="$2" current component entry full=''
    if [[ "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then workshop_status_printf '%s\n' '[FAIL] Paths must not contain line breaks.' >&2; return 2; fi
    if [[ "$path" == //* || "$path" == *\\* || "$path" =~ ^[[:alpha:]]: ]]; then
        workshop_status_printf '%s\n' '[FAIL] Use a standard POSIX path in Bash.' >&2; return 2
    fi
    [[ "$path" == /* ]] || path="$PWD/$path"
    local -a parts
    IFS=/ read -r -a parts <<< "$path"
    for component in "${parts[@]}"; do
        case "$component" in
            ''|.) continue ;;
            ..) full="${full%/*}" ;;
            *) full="$full/$component" ;;
        esac
        if [[ -L "${full:-/}" ]]; then workshop_status_printf '%s\n' '[FAIL] Destinations reached through symbolic links are not supported.' >&2; return 2; fi
    done
    full="${full:-/}"
    if [[ "$full" == / || "$full" == "$HOME" || "$full" == "$workshop" || "$full" -ef "$HOME" || "$full" -ef "$workshop" ]]; then
        workshop_status_printf '%s\n' '[FAIL] The home directory, filesystem root, or workshop root cannot be a destination.' >&2; return 2
    fi
    current="$full"
    while [[ -n "$current" ]]; do
        for component in docs scripts tests; do
            if [[ "$current" -ef "$workshop/$component" ]]; then workshop_status_printf '%s\n' '[FAIL] Workshop resource directories cannot be destinations.' >&2; return 2; fi
        done
        current="${current%/*}"
    done
    for current in docs scripts tests; do
        case "$full/" in "$workshop/$current/"*) workshop_status_printf '%s\n' '[FAIL] Workshop resource directories cannot be destinations.' >&2; return 2 ;; esac
    done
    if [[ -e "$full" ]]; then
        if [[ ! -d "$full" || ! -r "$full" || ! -x "$full" ]]; then workshop_status_printf '%s\n' '[FAIL] The destination is not a readable directory.' >&2; return 2; fi
        for entry in "$full"/* "$full"/.[!.]* "$full"/..?*; do
            if [[ -e "$entry" || -L "$entry" ]]; then workshop_status_printf '%s\n' '[FAIL] The destination is not empty. Existing files will not be overwritten.' >&2; return 2; fi
        done
    fi
    printf '%s\n' "$full"
}

download_sample() (
    set -e
    local target="$1" repository="$2" commit="$3" subdirectory="$4" track="$5" workshop="$6"
    local parent staging source required notice name normalized license=false payload cleanup
    target=$(safe_destination "$target" "$workshop")
    parent="${target%/*}"; parent="${parent:-/}"
    mkdir -p -- "$parent"
    staging="$parent/.workshop-download.$$.$RANDOM"
    (umask 077; mkdir -- "$staging")
    # Bash 3.2는 EXIT trap 전에 함수의 지역 변수를 해제할 수 있다.
    printf -v cleanup 'result=$?; trap - EXIT; rm -rf -- %q || result=1; if (( result != 0 )); then workshop_status_printf "[FAIL] Download failed. Check the destination state and retry with an empty path: %%s\\n" %q >&2; fi; exit "$result"' "$staging" "$target"
    trap "$cleanup" EXIT
    git init --quiet "$staging/checkout"
    git -C "$staging/checkout" remote add origin "$repository"
    git -C "$staging/checkout" fetch --quiet --depth 1 origin "$commit"
    git -C "$staging/checkout" -c advice.detachedHead=false -c core.autocrlf=false checkout --quiet --detach FETCH_HEAD
    [[ "$(git -C "$staging/checkout" rev-parse HEAD)" == "$commit" ]] || { workshop_status_printf '%s\n' '[FAIL] Commit verification failed.' >&2; exit 1; }
    source="$staging/checkout/$subdirectory"
    if [[ "$track" == java ]]; then
        for required in pom.xml web worker mvnw .mvn/wrapper/maven-wrapper.properties; do
            [[ -e "$source/$required" ]] || { workshop_status_printf '[FAIL] Required path not found: %s\n' "$required" >&2; exit 1; }
        done
    else
        for required in ContosoUniversity.sln ContosoUniversity.csproj packages.config; do
            [[ -f "$source/$required" ]] || { workshop_status_printf '[FAIL] Required path not found: %s\n' "$required" >&2; exit 1; }
        done
    fi
    payload="$staging/payload"
    mkdir "$payload"
    cp -Rp "$source/." "$payload/"
    if [[ -e "$payload/upstream-source.json" || -L "$payload/upstream-source.json" ]]; then
        workshop_status_printf '%s\n' '[FAIL] The source already contains upstream-source.json. Stopping without overwriting it.' >&2; exit 1
    fi
    for notice in "$staging/checkout/"*; do
        [[ -f "$notice" ]] || continue
        name="${notice##*/}"
        normalized=$(printf '%s' "$name" | LC_ALL=C tr '[:lower:]' '[:upper:]')
        [[ "$normalized" =~ ^(LICENSE|LICENCE|NOTICE|COPYING|COPYRIGHT)([._-].*)?$ ]] || continue
        if [[ -e "$payload/UPSTREAM-$name" || -L "$payload/UPSTREAM-$name" ]]; then
            workshop_status_printf '[FAIL] Source file conflicts with a license notice preservation path: %s\n' "$name" >&2; exit 1
        fi
        cp -p "$notice" "$payload/UPSTREAM-$name"
        [[ ! "$normalized" =~ ^(LICENSE|LICENCE|COPYING)([._-].*)?$ ]] || license=true
    done
    for notice in "$source/"*; do
        [[ -f "$notice" ]] || continue
        normalized=$(printf '%s' "${notice##*/}" | LC_ALL=C tr '[:lower:]' '[:upper:]')
        [[ ! "$normalized" =~ ^(LICENSE|LICENCE|COPYING)([._-].*)?$ ]] || license=true
    done
    # Production values are fixed URLs, SHA-1 and directory names, not user input.
    printf '{\n  "repository": "%s",\n  "commit": "%s",\n  "subdirectory": "%s",\n  "licenseFileFound": %s\n}\n' "$repository" "$commit" "$subdirectory" "$license" > "$payload/upstream-source.json"
    safe_destination "$target" "$workshop" >/dev/null
    [[ ! -d "$target" ]] || rmdir -- "$target"
    # mkdir reserves the destination; cp will never merge into another writer's directory.
    mkdir -- "$target"
    cp -Rp "$payload/." "$target/"
    workshop_status_printf '[PASS] Sample downloaded: %s\n' "$target"
    workshop_status_printf '[PASS] Source commit: %s / No Git repository created in the app directory\n' "$commit"
    if [[ "$license" == false ]]; then workshop_status_printf '%s\n' '[WARN] No source license file was found. Do not assume redistribution rights.'; fi
)

download_main() {
    local track='' requested='' destination='' engine workshop os
    while (( $# )); do
        case "$1" in
            --track|--container-engine|--destination)
                if (( $# < 2 )) || [[ "$2" == --* || -z "$2" ]]; then workshop_status_printf '[FAIL] A value is required for %s.\n' "$1" >&2; return 2; fi
                case "$1" in --track) track="$2" ;; --container-engine) requested="$2" ;; --destination) destination="$2" ;; esac
                shift 2 ;;
            --help|-h) printf '%s\n' './scripts/download-sample.sh --track java [--destination PATH] [--container-engine docker|podman]'; return 0 ;;
            *) workshop_status_printf '[FAIL] Unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
    done
    sample_definition "$track" || return $?
    source "$DOWNLOAD_SCRIPTS/check-prerequisites.sh"
    engine=$(resolve_engine "$requested") || return $?
    if [[ "$track" == dotnet ]]; then
        workshop_status_printf '%s\n' '[FAIL] For .NET, run ./scripts/download-sample.ps1 -Track dotnet in Windows PowerShell.'
        return 1
    fi
    os=$(uname -s)
    case "$os" in
        Darwin|Linux) ;;
        *) workshop_status_printf '%s\n' '[FAIL] Run this on macOS or Linux. In Windows PowerShell, run ./scripts/download-sample.ps1 -Track java.'; return 1 ;;
    esac
    workshop="$(cd "$DOWNLOAD_SCRIPTS/.." && pwd -P)"
    destination=$(safe_destination "${destination:-$workshop/$track}" "$workshop") || return $?
    bash "$DOWNLOAD_SCRIPTS/check-prerequisites.sh" --track java --container-engine "$engine" || {
        workshop_status_printf '%s\n' '[FAIL] Prerequisite checks did not pass; the sample was not downloaded.' >&2; return 1;
    }
    download_sample "$destination" "$SAMPLE_REPOSITORY" "$SAMPLE_COMMIT" "$SAMPLE_SUBDIRECTORY" "$track" "$workshop"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then download_main "$@"; exit $?; fi
