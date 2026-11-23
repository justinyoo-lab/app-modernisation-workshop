#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ] && [ -z "${ZSH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run source ../scripts/use-java.sh --jdk 8|25 in Bash or Zsh.' >&2
    return 2 2>/dev/null || exit 2
fi

if [ -n "${BASH_VERSION:-}" ]; then
    source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/terminal-output.sh"
else
    source "${${(%):-%x}:A:h}/terminal-output.sh"
fi

if [ -n "${BASH_VERSION:-}" ]; then
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        workshop_status_printf '%s\n' '[FAIL] Run source ../scripts/use-java.sh --jdk 8|25 in the current shell.' >&2
        exit 2
    fi
else
    case "$ZSH_EVAL_CONTEXT" in
        *:file) ;;
        *) workshop_status_printf '%s\n' '[FAIL] Run source ../scripts/use-java.sh --jdk 8|25 in the current shell.' >&2; exit 2 ;;
    esac
fi

_workshop_use_java() {
    local major='' sdkman_dir="${SDKMAN_DIR:-$HOME/.sdkman}" candidate identifier runtime compiler runtime_major compiler_major
    if [[ $# -ne 2 || "$1" != --jdk ]]; then
        workshop_status_printf '%s\n' '[FAIL] Usage: source ../scripts/use-java.sh --jdk 8|25' >&2
        return 2
    fi
    major="$2"
    case "$major" in
        8|25) ;;
        *) workshop_status_printf '%s\n' '[FAIL] Specify 8 or 25 as the --jdk value.' >&2; return 2 ;;
    esac
    if [[ ! -f ./mvnw ]]; then
        workshop_status_printf '%s\n' '[FAIL] Run this from the sample app root. No mvnw file was found in the current directory.' >&2
        return 1
    fi

    if [[ ! -r "$sdkman_dir/bin/sdkman-init.sh" ]]; then
        workshop_status_printf '[FAIL] SDKMAN initialization file not found: %s/bin/sdkman-init.sh\n' "$sdkman_dir" >&2
        return 1
    fi
    if ! source "$sdkman_dir/bin/sdkman-init.sh"; then
        workshop_status_printf '%s\n' '[FAIL] Failed to initialize SDKMAN.' >&2
        return 1
    fi

    identifier=$(
        if [[ -n "${ZSH_VERSION:-}" ]]; then setopt local_options no_nomatch; fi
        for candidate in "$sdkman_dir"/candidates/java/"$major".*; do
            [[ -x "$candidate/bin/java" && -x "$candidate/bin/javac" ]] || continue
            runtime=$("$candidate/bin/java" -version 2>&1) || continue
            if ! compiler=$("$candidate/bin/javac" -version 2>&1); then
                compiler=$("$candidate/bin/javac" --version 2>&1) || continue
            fi
            case "$runtime" in (*-ea*) continue ;; (*'version "'*) runtime="${runtime#*version \"}"; runtime="${runtime%%\"*}" ;; (*) continue ;; esac
            case "$compiler" in (*-ea*) continue ;; ('javac '*) compiler="${compiler#javac }" ;; (*) continue ;; esac
            case "$runtime" in (1.*) runtime="${runtime#1.}" ;; esac
            case "$compiler" in (1.*) compiler="${compiler#1.}" ;; esac
            runtime_major="${runtime%%.*}"
            compiler_major="${compiler%%.*}"
            if [[ "$runtime_major" == "$major" && "$compiler_major" == "$major" ]]; then
                printf '%s\n' "${candidate##*/}"
                break
            fi
        done
    )

    if [[ -z "$identifier" ]]; then
        workshop_status_printf '[FAIL] No runnable SDKMAN JDK %s was found. Check the installed JDKs and SDKMAN_DIR.\n' "$major" >&2
        return 1
    fi
    if ! sdk use java "$identifier"; then
        workshop_status_printf '[FAIL] Could not switch to JDK %s (%s) with SDKMAN.\n' "$major" "$identifier" >&2
        return 1
    fi
    export JAVA_HOME="$sdkman_dir/candidates/java/$identifier"
    export PATH="$JAVA_HOME/bin:$PATH"
    hash -r
    workshop_status_printf '[PASS] Selected SDKMAN JDK %s: %s\n' "$major" "$identifier"
}

_workshop_show_versions() {
    local result="$1"
    unset -f _workshop_use_java _workshop_show_versions
    if (( result != 0 )); then
        unset -f workshop_status_printf workshop_status_color_enabled workshop_status_color_allowed
        return "$result"
    fi
    workshop_status_printf '[INFO] java -version\n'
    if java -version; then
        :
    else
        result=$?
        workshop_status_printf '[FAIL] java -version failed.\n' >&2
        unset -f workshop_status_printf workshop_status_color_enabled workshop_status_color_allowed
        return "$result"
    fi
    workshop_status_printf '[INFO] javac -version\n'
    if javac -version; then
        :
    else
        result=$?
        workshop_status_printf '[FAIL] javac -version failed.\n' >&2
        unset -f workshop_status_printf workshop_status_color_enabled workshop_status_color_allowed
        return "$result"
    fi
    unset -f workshop_status_printf workshop_status_color_enabled workshop_status_color_allowed
}

if _workshop_use_java "$@"; then
    _workshop_show_versions 0
else
    _workshop_show_versions "$?"
fi
return $?
