#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./tests/use-java.tests.sh.' >&2
    return 2 2>/dev/null || exit 2
fi
set -e
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$ROOT/.test-output"
fixture="$ROOT/.test-output/java-shells.$$.$RANDOM"
(umask 077; mkdir "$fixture")
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/sdk/bin" "$fixture/app" "$fixture/no-app"
touch "$fixture/app/mvnw"
cat > "$fixture/sdk/bin/sdkman-init.sh" <<'FIXTURE'
if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ "$EXPECTED_NOMATCH" == "$options[nomatch]" && "$EXPECTED_LOCAL_OPTIONS" == "$options[localoptions]" ]] || return 1
fi
sdk() {
    [[ "$1" == use && "$2" == java ]] || return 1
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        [[ "$EXPECTED_NOMATCH" == "$options[nomatch]" && "$EXPECTED_LOCAL_OPTIONS" == "$options[localoptions]" ]] || return 1
    fi
    export JAVA_HOME="$SDKMAN_DIR/candidates/java/$3"
}
FIXTURE
for major in 8 25; do
    mkdir -p "$fixture/sdk/candidates/java/$major.0-test/bin"
    if [[ "$major" == 8 ]]; then version=1.8.0_400; else version=25; fi
    printf '#!/usr/bin/env bash\nprintf '\''openjdk version "%s"\\n'\''\n' "$version" > "$fixture/sdk/candidates/java/$major.0-test/bin/java"
    printf '#!/usr/bin/env bash\nprintf '\''javac %s\\n'\''\n' "$version" > "$fixture/sdk/candidates/java/$major.0-test/bin/javac"
    chmod +x "$fixture/sdk/candidates/java/$major.0-test/bin/"*
done
mkdir -p "$fixture/empty-sdk/bin" "$fixture/mismatch-sdk/bin" "$fixture/mismatch-sdk/candidates/java"
cp "$fixture/sdk/bin/sdkman-init.sh" "$fixture/empty-sdk/bin/"
cp "$fixture/sdk/bin/sdkman-init.sh" "$fixture/mismatch-sdk/bin/"
cp -Rp "$fixture/sdk/candidates/java/25.0-test" "$fixture/mismatch-sdk/candidates/java/8.0-test"
for shell in bash zsh; do
    command -v "$shell" >/dev/null 2>&1 || { printf 'FAIL: %s required for source tests\n' "$shell" >&2; exit 1; }
    for option in on off; do
        SDKMAN_DIR="$fixture/sdk" EXPECTED_NOMATCH="$option" "$shell" -c '
            cd "$2/app" || exit 1
            if [ -n "${ZSH_VERSION:-}" ]; then
                if [ "$EXPECTED_NOMATCH" = on ]; then setopt nomatch; else unsetopt nomatch; fi
                EXPECTED_LOCAL_OPTIONS="$options[localoptions]"
            fi
            if source "$1"; then exit 1; else test "$?" = 2 || exit 1; fi
            if source "$1" --wrong 8; then exit 1; else test "$?" = 2 || exit 1; fi
            for major in 8 25; do
                source "$1" --jdk "$major" || exit 1
                test "$JAVA_HOME" = "$SDKMAN_DIR/candidates/java/$major.0-test" || exit 1
                case "$PATH" in "$JAVA_HOME/bin:"*) ;; *) exit 1 ;; esac
                if typeset -f _workshop_use_java >/dev/null || typeset -f _workshop_show_versions >/dev/null ||
                    typeset -f workshop_status_printf >/dev/null || typeset -f workshop_status_color_enabled >/dev/null ||
                    typeset -f workshop_status_color_allowed >/dev/null; then exit 1; fi
                test -z "${_workshop_use_java_status+x}" || exit 1
            done
            if [ -n "${ZSH_VERSION:-}" ]; then test "$EXPECTED_NOMATCH" = "$options[nomatch]" || exit 1; fi
        ' _ "$ROOT/scripts/use-java.sh" "$fixture"
    done
    for scenario in invalid missing mismatched no-app no-sdk; do
        SDKMAN_DIR="$fixture/sdk" "$shell" -c '
            cd "$2/app" || exit 1
            if [ -n "${ZSH_VERSION:-}" ]; then
                EXPECTED_NOMATCH="$options[nomatch]"
                EXPECTED_LOCAL_OPTIONS="$options[localoptions]"
            fi
            major=8
            case "$3" in
                invalid) major=21 ;;
                missing) major=25; SDKMAN_DIR="$2/empty-sdk" ;;
                mismatched) SDKMAN_DIR="$2/mismatch-sdk" ;;
                no-app) cd "$2/no-app" || exit 1 ;;
                no-sdk) SDKMAN_DIR="$2/missing-sdk" ;;
            esac
            if source "$1" --jdk "$major"; then exit 1; else result=$?; fi
            if [ "$3" = invalid ]; then test "$result" = 2 || exit 1; else test "$result" = 1 || exit 1; fi
            if typeset -f _workshop_use_java >/dev/null || typeset -f _workshop_show_versions >/dev/null ||
                typeset -f workshop_status_printf >/dev/null || typeset -f workshop_status_color_enabled >/dev/null ||
                typeset -f workshop_status_color_allowed >/dev/null; then exit 1; fi
            test -z "${_workshop_use_java_status+x}" || exit 1
            printf "caller survived\n"
        ' _ "$ROOT/scripts/use-java.sh" "$fixture" "$scenario"
    done
    if "$shell" "$ROOT/scripts/use-java.sh" --jdk 8; then printf 'FAIL: direct execution accepted\n' >&2; exit 1; fi
done
printf 'PASS: Bash/Zsh Java selection, errors, cleanup and caller options\n'
