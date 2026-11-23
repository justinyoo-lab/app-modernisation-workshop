#!/usr/bin/env bash

workshop_status_color_allowed() {
    [[ -z "${NO_COLOR:-}" && "${TERM:-}" != dumb && -z "${CI:-}" ]]
}

workshop_status_color_enabled() {
    [[ -t 1 ]] && workshop_status_color_allowed
}

workshop_status_printf() {
    local output label color
    printf -v output "$@"
    case "$output" in
        '[PASS]'*) label=PASS; color=32 ;;
        '[FAIL]'*) label=FAIL; color=31 ;;
        '[WARN]'*) label=WARN; color=33 ;;
        '[MANUAL]'*) label=MANUAL; color=36 ;;
        '[INFO]'*) label=INFO; color=34 ;;
        *) printf '%s' "$output"; return ;;
    esac
    if workshop_status_color_enabled; then
        printf '\033[%sm[%s]\033[0m%s' "$color" "$label" "${output:$(( ${#label} + 2 ))}"
    else
        printf '%s' "$output"
    fi
}
