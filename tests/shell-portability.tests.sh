#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./tests/shell-portability.tests.sh.' >&2
    return 2 2>/dev/null || exit 2
fi
set -e
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$ROOT/.test-output"
fixture="$ROOT/.test-output/portability.$$.$RANDOM"
(umask 077; mkdir "$fixture")
trap 'rm -rf -- "$fixture"' EXIT
source "$ROOT/scripts/terminal-output.sh"

status_output=$(workshop_status_printf '[PASS] status text\n')
[[ "$status_output" == '[PASS] status text' ]]
for entry in 'PASS 32' 'FAIL 31' 'WARN 33' 'MANUAL 36' 'INFO 34'; do
    status="${entry%% *}"
    color="${entry#* }"
    status_output=$(workshop_status_color_enabled() { return 0; }; workshop_status_printf "[$status] status text\n")
    printf -v expected '\033[%sm[%s]\033[0m status text' "$color" "$status"
    [[ "$status_output" == "$expected" ]] || {
        printf 'FAIL: colored %s status\n' "$status" >&2; exit 1;
    }
done
if ! NO_COLOR= TERM=xterm CI= workshop_status_color_allowed; then exit 1; fi
if NO_COLOR=1 TERM=xterm CI= workshop_status_color_allowed; then exit 1; fi
if NO_COLOR= TERM=dumb CI= workshop_status_color_allowed; then exit 1; fi
if NO_COLOR= TERM=xterm CI=1 workshop_status_color_allowed; then exit 1; fi
NO_COLOR= TERM=xterm CI= workshop_status_color_allowed
status_output=$(workshop_status_printf '[WARN] redirected status\n' 2>"$fixture/stderr")
[[ "$status_output" == '[WARN] redirected status' ]] || { printf 'FAIL: redirected status text: %q\n' "$status_output"; exit 1; }
[[ ! -s "$fixture/stderr" ]] || { printf 'FAIL: redirected status wrote stderr: %s\n' "$(cat "$fixture/stderr")"; exit 1; }
workshop_status_printf '[FAIL] stderr status\n' 2>"$fixture/stderr" >&2
[[ "$(cat "$fixture/stderr")" == '[FAIL] stderr status' ]]
source "$ROOT/scripts/check-prerequisites.sh"
CHECK_FAILURES=0
check_result FAIL fixture 'unchanged message' > "$fixture/check-result"
check_output=$(cat "$fixture/check-result")
[[ "$check_output" == '[FAIL] [Bash] fixture: unchanged message' && "$CHECK_FAILURES" == 1 ]]
unset -f workshop_status_printf workshop_status_color_enabled workshop_status_color_allowed

# portability-patterns-begin
cat > "$fixture/forbidden" <<'PATTERNS'
(^|[^[:alnum:]_])(mapfile|readarray|coproc|BASHPID|EPOCHSECONDS|EPOCHREALTIME)([^[:alnum:]_]|$)
(declare|local|typeset)[[:space:]]+-[^[:space:]]*[Ang]
\$\{[[:alnum:]_]+(\[[^]]+\])?([,][,]?|\^\^?|@[QEPAaKkUuLl])[^}]*\}
\[\[[[:space:]]+-v[[:space:]]
;;&|;&|\|&|&>>
wait[[:space:]]+-n
\{[[:alpha:]_][[:alnum:]_]*\}[<>]
shopt.*(globstar|lastpipe|inherit_errexit)
\[[[:space:]]*-[0-9]+[[:space:]]*\]
%[(][^)]*[)]T
set[[:space:]]+-[[:alpha:]]*u
set[[:space:]]+-o[[:space:]]+nounset
sed[[:space:]]+-i|readlink[[:space:]]+-f|(^|[^[:alnum:]_])realpath([^[:alnum:]_]|$)|date[[:space:]]+-d
grep[[:space:]]+-P|stat[[:space:]]+-[cf]|sort[[:space:]]+-V|find.*-printf
xargs[[:space:]]+-r|(^|[^[:alnum:]_])timeout([^[:alnum:]_]|$)|head[[:space:]]+-n[[:space:]]+-[0-9]+
(^|[^[:alnum:]_])tac([^[:alnum:]_]|$)|base64[[:space:]]+-w
PATTERNS
# portability-patterns-end

for script in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
    relative="${script#"$ROOT/"}"
    bash -n "$script"
    IFS= read -r first < "$script"
    [[ "$first" == '#!/usr/bin/env bash' ]] || { printf 'FAIL: shebang %s\n' "$relative"; exit 1; }
    awk '/^# portability-patterns-begin$/ { skip=1; next }
        /^# portability-patterns-end$/ { skip=0; next }
        !skip && !/^[[:space:]]*#/ { print }' "$script" > "$fixture/code"
    if LC_ALL=C grep -En -f "$fixture/forbidden" "$fixture/code"; then
        printf 'FAIL: nonportable syntax in %s\n' "$relative" >&2; exit 1
    fi
    case "$relative" in
        tests/*) ;;
        scripts/*)
            awk -v file="$relative" '
                /^[a-zA-Z_][a-zA-Z_0-9]*\(\)/ { fn=$1; sub(/\(\).*/, "", fn) }
                /^[[:space:]]*#/ { next }
                /(^|[^[:alnum:]_])(brew|sw_vers|apt-get|apt-cache|dpkg-query|sha256sum)([^[:alnum:]_]|$)/ {
                    if (fn !~ /^(check_homebrew|ensure_homebrew|prepare_sdkman_dependencies|microsoft_apt_candidate|azd_file_hash|azd_package_owned|install_linux_azd|update_azure_tool|linux_install_supported|install_linux_gh|install_modernize|install_missing_tools)$/) {
                        print "FAIL: OS-specific command outside allowed function: " file ":" NR
                        failed=1
                    }
                }
                END { exit failed }' "$script"
            ;;
    esac
    expected=100755
    case "$relative" in scripts/use-java.sh|scripts/terminal-output.sh|scripts/java-deployment.sh) expected=100644 ;; esac
    if git -C "$ROOT" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1; then
        mode=$(git -C "$ROOT" ls-files -s -- "$relative")
        mode="${mode%% *}"
    else
        [[ ! -x "$script" ]] || { printf 'FAIL: New source-only file is executable: %s\n' "$relative" >&2; exit 1; }
        mode=$expected
    fi
    [[ "$mode" == "$expected" ]] || { printf 'FAIL: Git mode %s expected %s: %s\n' "$mode" "$expected" "$relative" >&2; exit 1; }
done
zsh -n "$ROOT/scripts/use-java.sh"

mkdir "$fixture/bin"
for command_name in uname dirname curl git brew; do
    printf '#!/bin/sh\nprintf "unexpected command\\n" >> "$GUARD_LOG"\nexit 1\n' > "$fixture/bin/$command_name"
    chmod +x "$fixture/bin/$command_name"
done
for script in check-prerequisites install-prerequisites download-sample; do
    for shell in sh zsh; do
        interpreter=$(command -v "$shell")
        if [[ "$shell" == sh && -n "$("$interpreter" -c 'printf "%s" "${BASH_VERSION:-}"')" ]]; then
            output=$("$interpreter" "$ROOT/scripts/$script.sh" --help)
            [[ "$output" == "./scripts/$script.sh"* ]] || {
                printf 'FAIL: Bash-backed sh execution %s\n' "$script"; exit 1;
            }
            continue
        fi
        : > "$fixture/guard-log"
        if output=$(GUARD_LOG="$fixture/guard-log" PATH="$fixture/bin:$PATH" "$interpreter" "$ROOT/scripts/$script.sh" --help 2>&1); then
            printf 'FAIL: %s accepted %s\n' "$script" "$shell"; exit 1
        fi
        [[ "$output" == *'[FAIL]'* && "$output" == *"./scripts/$script.sh"* && ! -s "$fixture/guard-log" ]] || {
            printf 'FAIL: early shell guard: %s %s\n%s\n' "$script" "$shell" "$output"; exit 1;
        }
    done
    output=$("$ROOT/scripts/$script.sh" --help)
    [[ "$output" == "./scripts/$script.sh"* ]] || { printf 'FAIL: direct execution %s\n' "$script"; exit 1; }
done
printf 'PASS: Bash %s portability, Git modes, shell guards and direct execution\n' "$BASH_VERSION"
