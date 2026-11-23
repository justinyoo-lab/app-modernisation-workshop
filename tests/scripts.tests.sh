#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
    printf '%s\n' '[FAIL] Run ./tests/scripts.tests.sh.' >&2
    return 2 2>/dev/null || exit 2
fi
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/scripts/check-prerequisites.sh"
source "$ROOT/scripts/download-sample.sh"
mkdir -p "$ROOT/.test-output"
TEMPORARY="$ROOT/.test-output/bash.$$.$RANDOM"
(umask 077; mkdir "$TEMPORARY")
trap 'rm -rf -- "$TEMPORARY"' EXIT
PASSED=0

assert() {
    local name="$1"; shift
    if ! "$@"; then printf 'FAILED: %s\n' "$name" >&2; exit 1; fi
    PASSED=$((PASSED + 1))
}

bash -n "$ROOT/scripts/check-prerequisites.sh"
bash -n "$ROOT/scripts/download-sample.sh"
bash -n "$ROOT/scripts/use-java.sh"
nvm_fixture="$TEMPORARY/nvm"
mkdir -p "$nvm_fixture"
printf '%s\n' 'nvm() { [[ "$*" == "use --silent default" ]] || return 1; node() { printf "v24.18.0\n"; }; }' > "$nvm_fixture/nvm.sh"
nvm_output=$(
    NVM_DIR="$nvm_fixture"
    tool_path() { printf ''; }
    initialize_node_environment
    node --version
)
assert 'noninteractive nvm activates default Node' test "$nvm_output" = v24.18.0
existing_node_output=$(
    NVM_DIR="$nvm_fixture"
    tool_path() { printf '/usr/bin/node\n'; }
    node() { printf 'v22.1.0\n'; }
    initialize_node_environment
    node --version
)
assert 'existing native Node preserved' test "$existing_node_output" = v22.1.0
unset AZD_CONTAINER_RUNTIME
assert 'default engine' test "$(resolve_engine '')" = docker
assert 'explicit engine' test "$(resolve_engine podman)" = podman
export AZD_CONTAINER_RUNTIME=podman
assert 'configured engine' test "$(resolve_engine '')" = podman
if resolve_engine docker >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
if resolve_engine nerdctl >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
unset AZD_CONTAINER_RUNTIME
assert 'azd minimum' minimum_version 'azd version 1.37.3 (commit abc)' 1.37.3
if minimum_version 1.37.2 1.37.3; then exit 1; else PASSED=$((PASSED + 1)); fi
if minimum_version 22.0.0-rc.1 22.0.0; then exit 1; else PASSED=$((PASSED + 1)); fi

for platform in Darwin Linux; do
    platform_output=$(
        uname() { printf '%s\n' "$platform"; }
        check_homebrew() { check_result PASS fixture-homebrew 'Homebrew check'; }
        check_glibc() { check_result PASS fixture-glibc 'Linux glibc check'; }
        check_common() { check_result PASS fixture-common 'common checks reached'; }
        check_java_sdks() { check_result PASS fixture-sdks 'SDK checks reached'; }
        prerequisite_main --track java --container-engine docker
    )
    assert "$platform reaches common checks" grep -q 'fixture-common' <<< "$platform_output"
    assert "$platform reaches SDK checks" grep -q 'fixture-sdks' <<< "$platform_output"
    if [[ "$platform" == Darwin ]]; then
        assert 'Homebrew checked before common tools' grep -q 'fixture-homebrew' <<< "$platform_output"
        assert 'macOS skips glibc check' test "${platform_output#*fixture-glibc}" = "$platform_output"
    else
        assert 'Linux does not use Homebrew' test "${platform_output#*fixture-homebrew}" = "$platform_output"
        assert 'Linux checks glibc before common tools' grep -q 'fixture-glibc' <<< "$platform_output"
    fi
done
runtime_output_for_case() {
    local case_name="$1"
    unset AZD_CONTAINER_RUNTIME
    uname() { printf 'Linux\n'; }
    check_glibc() { :; }
    check_common() { :; }
    check_java_sdks() { :; }
    case "$case_name" in
        default) prerequisite_main --track java ;;
        docker) export AZD_CONTAINER_RUNTIME=docker; prerequisite_main --track java --container-engine docker ;;
        podman-unconfigured) prerequisite_main --track java --container-engine podman ;;
        podman-configured) export AZD_CONTAINER_RUNTIME=podman; prerequisite_main --track java ;;
    esac
    if [[ "$case_name" == default || "$case_name" == podman-unconfigured ]]; then
        [[ -z "${AZD_CONTAINER_RUNTIME:-}" ]]
    elif [[ "$case_name" == docker ]]; then
        [[ "$AZD_CONTAINER_RUNTIME" == docker ]]
    else
        [[ "$AZD_CONTAINER_RUNTIME" == podman ]]
    fi
}
for runtime_case in default docker podman-unconfigured podman-configured; do
    runtime_output=$(runtime_output_for_case "$runtime_case")
    if [[ "$runtime_case" == podman-unconfigured ]]; then
        assert 'unconfigured Podman reminder uses Bash syntax' grep -Fxq 'Before running azd, run export AZD_CONTAINER_RUNTIME=podman in the current shell.' <<< "$runtime_output"
    else
        assert "$runtime_case needs no runtime reminder" test "${runtime_output#*AZD_CONTAINER_RUNTIME}" = "$runtime_output"
    fi
done
for entry in prerequisite_main install_prerequisite_main download_main; do
    source "$ROOT/scripts/install-prerequisites.sh"
    unsupported=$(
        uname() { printf '%s\n' FreeBSD; }
        if "$entry" --track java 2>&1; then exit 1; else printf 'exit=%s\n' "$?"; fi
    )
    assert "$entry unsupported OS rejected" grep -q 'FAIL.*Windows PowerShell' <<< "$unsupported"
    dotnet_output=$(if "$entry" --track dotnet; then exit 1; else printf 'exit=%s\n' "$?"; fi 2>&1)
    assert "$entry dotnet rejected" grep -q 'FAIL.*Windows PowerShell' <<< "$dotnet_output"
done

CALLS="$TEMPORARY/calls"
STOPPED=0
probe() {
    printf '%s\n' "$*" >> "$CALLS"
    PROBE_CODE=0; PROBE_TEXT=''
    case "$2" in
        --version) PROBE_TEXT="$1 version 5.4.0" ;;
        info) if (( STOPPED )); then PROBE_CODE=1; else PROBE_TEXT=linux; fi ;;
        build) PROBE_TEXT=--platform ;;
        buildx) PROBE_CODE=127 ;;
    esac
}
CHECK_FAILURES=0
check_container podman
assert 'podman without docker' test "$CHECK_FAILURES" = 0
if grep -q '^docker ' "$CALLS"; then exit 1; else PASSED=$((PASSED + 1)); fi
: > "$CALLS"
STOPPED=1
CHECK_FAILURES=0
check_container docker
assert 'stopped docker fails' test "$CHECK_FAILURES" -gt 0
if grep -q '^podman ' "$CALLS"; then exit 1; else PASSED=$((PASSED + 1)); fi
source "$ROOT/scripts/check-prerequisites.sh"

container_output=$(
    CHECK_CONTEXT='Linux Bash'
    tool_path() { printf '%s\n' '/usr/bin/docker'; }
    probe() {
        PROBE_CODE=0; PROBE_TEXT=''
        case "$2" in
            (--version) PROBE_TEXT='Docker version 29.0.0' ;;
            (info) PROBE_TEXT=linux ;;
            (build) PROBE_TEXT=--platform ;;
            (buildx) PROBE_TEXT='v0.20.0' ;;
        esac
    }
    CHECK_FAILURES=0
    check_container docker
)
assert 'container CLI path shown' grep -q 'PASS.*container-cli.*CLI is available.*path: /usr/bin/docker' <<< "$container_output"
assert 'server location not inferred' grep -q 'PASS.*container-engine.*does not verify where the engine is installed' <<< "$container_output"
assert 'buildx is only version lookup' grep -q 'PASS.*builder:.*Retrieved the Buildx version.*An actual build has not been tested' <<< "$container_output"
assert 'workload manual verification' grep -q 'MANUAL.*container-workload.*do not guarantee that the workload will succeed' <<< "$container_output"

common_output=$(
    CHECK_CONTEXT='Linux Bash'
    tool_path() { printf '/usr/bin/%s\n' "$1"; }
    probe() {
        PROBE_CODE=0; PROBE_TEXT=''
        case "$1 $2" in
            ('git --version') PROBE_TEXT='git version 2.50.0' ;;
            ('node --version') PROBE_TEXT='v22.1.0' ;;
            ('az version') PROBE_TEXT='{}' ;;
            ('az extension') PROBE_TEXT='1.3.0' ;;
            ('az account')
                if [[ "$*" == *'--query state'* ]]; then PROBE_TEXT=Enabled
                elif [[ "$*" == *'--query tenantId'* ]]; then PROBE_TEXT='11111111-2222-3333-4444-555555555555'
                elif [[ "$*" == *'--query [[id,name]]'* ]]; then PROBE_TEXT=$'subscription-id\tSubscription name'
                else PROBE_CODE=1; fi ;;
            ('az cloud') PROBE_TEXT='https://management.example.invalid/' ;;
            ('az rest') PROBE_TEXT='Example tenant' ;;
            ('az provider') PROBE_TEXT=Registered ;;
            ('azd version') PROBE_TEXT='azd version 1.37.3' ;;
            ('modernize --version') PROBE_TEXT='modernize 1.0.76' ;;
            ('gh --version') PROBE_TEXT='gh version 2.45.0' ;;
        esac
    }
    check_container() { :; }
    CHECK_FAILURES=0
    check_common docker
)
assert 'Azure identity shown for manual confirmation' grep -q 'MANUAL.*azure-subscription.*subscription-id' <<< "$common_output"
assert 'Azure subscription format' grep -Fxq '[MANUAL] [Linux Bash] azure-subscription: Subscription name (subscription-id)' <<< "$common_output"
assert 'Azure tenant name and ID require confirmation' grep -Fxq '[MANUAL] [Linux Bash] azure-tenant: Example tenant (11111111-2222-3333-4444-555555555555)' <<< "$common_output"
if grep 'azure-subscription' <<< "$common_output" | grep -q '11111111-2222-3333-4444-555555555555'; then exit 1; else PASSED=$((PASSED + 1)); fi
assert 'Azure CLI path identified' grep -q 'PASS.*Linux Bash.*az.*usr/bin/az' <<< "$common_output"
assert 'Java PostgreSQL provider checked' grep -q 'PASS.*Microsoft.DBforPostgreSQL' <<< "$common_output"
assert 'Copilot app requires manual terminal check' grep -q 'MANUAL.*copilot-app:.*terminal access' <<< "$common_output"
assert 'Azure permissions manual check scoped to Azure' grep -Fq '[MANUAL] [Azure (manual check)] azure-access:' <<< "$common_output"

for scenario in minimum supported old unavailable unrecognized; do
    glibc_output=$(
        probe() {
            PROBE_CODE=0
            case "$scenario" in
                (minimum) PROBE_TEXT='glibc 2.27' ;;
                (supported) PROBE_TEXT='glibc 2.39' ;;
                (old) PROBE_TEXT='glibc 2.26' ;;
                (unavailable) PROBE_CODE=127; PROBE_TEXT='' ;;
                (unrecognized) PROBE_TEXT='musl libc (x86_64)' ;;
            esac
        }
        CHECK_FAILURES=0
        check_glibc
        printf 'failures=%s\n' "$CHECK_FAILURES"
    )
    case "$scenario" in
        minimum|supported) expected=0 ;;
        *) expected=1 ;;
    esac
    assert "glibc prerequisite $scenario" grep -q "^failures=$expected$" <<< "$glibc_output"
done
assert 'unrecognized glibc gives supported-distro guidance' grep -q 'FAIL.*glibc.*Could not determine the glibc version.*supported glibc-based Linux distribution' <<< "$glibc_output"
old_glibc_output=$(
    probe() { PROBE_CODE=0; PROBE_TEXT='glibc 2.26'; }
    CHECK_FAILURES=0
    check_glibc
)
assert 'old glibc gives safe remediation' grep -q 'FAIL.*glibc.*2.27 or later.*Do not install glibc separately; use a supported Linux distribution' <<< "$old_glibc_output"

missing_output=$(
    CHECK_CONTEXT='Linux Bash'
    probe() {
        PROBE_TEXT=''; PROBE_CODE=0
        case "$1 $2" in
            ('node --version'|'azd version') PROBE_CODE=127 ;;
            ('az version') PROBE_CODE=127 ;;
        esac
    }
    check_container() { :; }
    CHECK_FAILURES=0
    check_common docker
)
assert 'missing Node is scoped' grep -q 'FAIL.*Linux Bash.*node.*PATH.*Bash environment' <<< "$missing_output"
assert 'missing azd is scoped' grep -q 'FAIL.*Linux Bash.*azd.*PATH.*Bash environment' <<< "$missing_output"

for scenario in ready missing-modernize broken-modernize missing-gh old-gh broken-gh unauthenticated; do
    tool_output=$(
        probe() {
            PROBE_CODE=0; PROBE_TEXT=''
            case "$1 $2" in
                ('modernize --version') PROBE_TEXT='modernize 1.0.76'
                    case "$scenario" in (missing-modernize) PROBE_CODE=127 ;; (broken-modernize) PROBE_CODE=1 ;; esac ;;
                ('gh --version') PROBE_TEXT='gh version 2.45.0'
                    case "$scenario" in (missing-gh) PROBE_CODE=127 ;; (old-gh) PROBE_TEXT='gh version 2.44.0' ;; (broken-gh) PROBE_CODE=1 ;; esac ;;
                ('gh auth') [[ "$scenario" != unauthenticated ]] || PROBE_CODE=1 ;;
                (*) return 1 ;;
            esac
        }
        CHECK_FAILURES=0
        check_modernize_tools
        printf 'failures=%s\n' "$CHECK_FAILURES"
    )
    if [[ "$scenario" == ready ]]; then expected=0; else expected=1; fi
    assert "modernization prerequisite $scenario" grep -q "^failures=$expected$" <<< "$tool_output"
done
mkdir -p "$TEMPORARY/home/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMPORARY/home/.local/bin/modernize"
chmod +x "$TEMPORARY/home/.local/bin/modernize"
hidden_modernize=$(
    HOME="$TEMPORARY/home"
    uname() { printf 'Linux\n'; }
    probe() { PROBE_CODE=127; PROBE_TEXT=''; }
    CHECK_FAILURES=0
    check_modernize_tools
)
assert 'installed Modernize outside PATH explains reload' grep -q 'FAIL.*modernize.*new terminal' <<< "$hidden_modernize"
for code in 0 1 127; do
    brew_output=$(
        probe() { PROBE_CODE="$code"; PROBE_TEXT='Homebrew fixture'; }
        CHECK_FAILURES=0
        check_homebrew
        printf 'failures=%s\n' "$CHECK_FAILURES"
    )
    if [[ "$code" == 0 ]]; then expected=0; else expected=1; fi
    assert "Homebrew exit $code" grep -q "^failures=$expected$" <<< "$brew_output"
    if [[ "$code" != 0 ]]; then assert 'Homebrew failure gives direct installer help' grep -q './scripts/install-prerequisites.sh' <<< "$brew_output"; fi
done

tenant_failure_output=$(
    probe() {
        PROBE_CODE=0; PROBE_TEXT=''
        case "$1 $2" in
            ('az account')
                if [[ "$*" == *'--query tenantId'* ]]; then PROBE_TEXT='11111111-2222-3333-4444-555555555555'
                else PROBE_TEXT=$'subscription-id\tSubscription name'; fi ;;
            ('az cloud') PROBE_TEXT='https://management.example.invalid/' ;;
            ('az rest') PROBE_CODE=1; PROBE_TEXT='access denied' ;;
        esac
    }
    CHECK_FAILURES=0
    check_azure_identity
    test "$CHECK_FAILURES" = 0
)
assert 'tenant name access failure warns' grep -q 'WARN.*azure-tenant' <<< "$tenant_failure_output"
assert 'tenant ID retained on name lookup failure' grep -q 'WARN.*azure-tenant.*11111111-2222-3333-4444-555555555555' <<< "$tenant_failure_output"
assert 'subscription still shown on tenant lookup failure' grep -q 'MANUAL.*azure-subscription.*Subscription name' <<< "$tenant_failure_output"

invalid_tenant_output=$(
    probe() {
        PROBE_CODE=0; PROBE_TEXT=''
        case "$1 $2" in
            ('az account')
                if [[ "$*" == *'--query tenantId'* ]]; then PROBE_TEXT="invalid' query"
                else PROBE_TEXT=$'subscription-id\tSubscription name'; fi ;;
            (*) printf 'unexpected Azure call\n' >&2; return 1 ;;
        esac
    }
    CHECK_FAILURES=0
    check_azure_identity
)
assert 'invalid tenant ID cannot be used in a query' grep -q 'WARN.*azure-tenant' <<< "$invalid_tenant_output"
invalid_subscription_output=$(
    probe() { PROBE_CODE=0; PROBE_TEXT='malformed subscription'; }
    CHECK_FAILURES=0
    check_azure_identity
)
assert 'invalid subscription output warns' grep -q 'WARN.*azure-subscription' <<< "$invalid_subscription_output"

machine_output=$(
    uname() { printf '%s\n' Darwin; }
    probe() {
        PROBE_CODE=0; PROBE_TEXT=''
        case "$2" in
            (--version) PROBE_TEXT='podman version 5.4.0' ;;
            (info) PROBE_TEXT=linux ;;
            (machine) PROBE_CODE=1 ;;
            (build) PROBE_TEXT=--platform ;;
        esac
    }
    CHECK_FAILURES=0
    check_container podman
    test "$CHECK_FAILURES" = 0
)
assert 'machine lookup failure warns' grep -q 'WARN.*podman-machine' <<< "$machine_output"

export SDKMAN_DIR="$TEMPORARY/sdkman"
mkdir -p "$SDKMAN_DIR/bin"
printf 'sdk() { echo "SDKMAN fixture"; }\n' > "$SDKMAN_DIR/bin/sdkman-init.sh"
for v in 8 25; do
    mkdir -p "$SDKMAN_DIR/candidates/java/$v-test/bin"
    if [[ "$v" == 8 ]]; then version=1.8.0_400; else version="$v"; fi
    printf '#!/usr/bin/env bash\nprintf '\''openjdk version "%s"\\n'\'' >&2\n' "$version" > "$SDKMAN_DIR/candidates/java/$v-test/bin/java"
    printf '#!/usr/bin/env bash\nprintf '\''javac %s\\n'\''\n' "$version" > "$SDKMAN_DIR/candidates/java/$v-test/bin/javac"
    chmod +x "$SDKMAN_DIR/candidates/java/$v-test/bin/"*
done
CHECK_FAILURES=0
check_java_sdks
assert 'JDK 8 and 25 alone satisfy SDKMAN prerequisites' test "$CHECK_FAILURES" = 0
mv "$SDKMAN_DIR/candidates/java/25-test" "$TEMPORARY/moved-jdk"
CHECK_FAILURES=0
check_java_sdks
assert 'missing JDK fails' test "$CHECK_FAILURES" = 1

java_selector_fixture="$TEMPORARY/java-selector"
mkdir -p "$java_selector_fixture/bin" "$java_selector_fixture/app"
touch "$java_selector_fixture/app/mvnw"
printf '%s\n' 'sdk() { [[ "$1" == use && "$2" == java ]] || return 1; printf "%s\n" "$3" > "$SDKMAN_DIR/selected"; export JAVA_HOME="$SDKMAN_DIR/candidates/java/$3"; PATH="$JAVA_HOME/bin:$PATH"; }' > "$java_selector_fixture/bin/sdkman-init.sh"
for v in 8 25; do
    identifier="$v.0-test"
    mkdir -p "$java_selector_fixture/candidates/java/$identifier/bin"
    if [[ "$v" == 8 ]]; then version=1.8.0_400; else version="$v.0.1"; fi
    printf '#!/usr/bin/env bash\nprintf '\''openjdk version "%s"\\n'\'' >&2\n' "$version" > "$java_selector_fixture/candidates/java/$identifier/bin/java"
    printf '#!/usr/bin/env bash\nprintf '\''javac %s\\n'\''\n' "$version" > "$java_selector_fixture/candidates/java/$identifier/bin/javac"
    chmod +x "$java_selector_fixture/candidates/java/$identifier/bin/"*
done
sequence_output=$(SDKMAN_DIR="$java_selector_fixture" bash -c '
    cd "$2" &&
    source "$1" --jdk 8 &&
    source "$1" --jdk 25
' _ "$ROOT/scripts/use-java.sh" "$java_selector_fixture/app" 2>&1)
for major in 8 25; do
    assert "select and verify JDK $major" grep -q "Selected SDKMAN JDK $major: $major.0-test" <<< "$sequence_output"
done
assert 'baseline reports Java version check' grep -q '\[INFO\] java -version' <<< "$sequence_output"
assert 'baseline reports compiler version check' grep -q '\[INFO\] javac -version' <<< "$sequence_output"
assert 'show selected Java version output' grep -q 'openjdk version "25.0.1"' <<< "$sequence_output"
assert 'show selected compiler version output' grep -q 'javac 25.0.1' <<< "$sequence_output"
for major in 17 21; do
    SDKMAN_DIR="$java_selector_fixture" bash -c '
        cd "$2" || exit 1
        if source "$1" --jdk "$3"; then exit 1; else test "$?" = 2; fi
    ' _ "$ROOT/scripts/use-java.sh" "$java_selector_fixture/app" "$major" >/dev/null 2>&1
    assert "unsupported JDK $major does not change selection" test "$(cat "$java_selector_fixture/selected")" = 25.0-test
done
if bash "$ROOT/scripts/use-java.sh" --jdk 8 >/dev/null 2>&1; then
    printf '%s\n' 'FAILED: require sourcing to change current shell' >&2; exit 1
else
    PASSED=$((PASSED + 1))
fi

if safe_destination "$ROOT" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
if safe_destination "$ROOT/docs/child" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
if [[ "$ROOT/DOCS" -ef "$ROOT/docs" ]]; then
    if safe_destination "$ROOT/DOCS/child" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
fi
if safe_destination "$HOME" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
if safe_destination '//server/share/app' "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
if safe_destination 'C:\workshops\app' "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
mkdir "$TEMPORARY/existing"
printf preserve > "$TEMPORARY/existing/.hidden"
if safe_destination "$TEMPORARY/existing" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
assert 'preserve existing' test "$(cat "$TEMPORARY/existing/.hidden")" = preserve

UPSTREAM="$TEMPORARY/upstream"
mkdir -p "$UPSTREAM/asset-manager/.mvn/wrapper" "$UPSTREAM/asset-manager/web" "$UPSTREAM/asset-manager/worker"
for f in pom.xml mvnw .gitignore .mvn/wrapper/maven-wrapper.properties web/test worker/test; do
    printf fixture > "$UPSTREAM/asset-manager/$f"
done
chmod +x "$UPSTREAM/asset-manager/mvnw"
printf '#!/usr/bin/env bash\nexit 0\n' > "$UPSTREAM/asset-manager/mvnw"
printf 'Fixture license\n' > "$UPSTREAM/LICENSE"
printf 'Fixture notice\n' > "$UPSTREAM/NOTICE.md"
printf 'Fixture alternate license\n' > "$UPSTREAM/license-MIT.txt"
printf 'Fixture copyright\n' > "$UPSTREAM/COPYRIGHT"
printf '<project><properties><java.version>1.8</java.version></properties></project>\n' > "$UPSTREAM/asset-manager/pom.xml"
git init --quiet "$UPSTREAM"
git -C "$UPSTREAM" config core.autocrlf false
git -C "$UPSTREAM" add .
git -C "$UPSTREAM" update-index --chmod=+x asset-manager/mvnw
git -C "$UPSTREAM" -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m $'Fixture\n\nCo-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>'
COMMIT=$(git -C "$UPSTREAM" rev-parse HEAD)
TARGET="$TEMPORARY/download with spaces"
download_sample "$TARGET" "$UPSTREAM" "$COMMIT" asset-manager java "$ROOT"
assert 'flattened Maven project' test -f "$TARGET/pom.xml"
assert 'wrapper files preserved' test -f "$TARGET/.mvn/wrapper/maven-wrapper.properties"
assert 'executable wrapper' test -x "$TARGET/mvnw"
assert 'hidden files preserved' test -f "$TARGET/.gitignore"
if grep -Eq '^/(java|dotnet)/$' "$ROOT/.gitignore"; then exit 1; else PASSED=$((PASSED + 1)); fi
assert 'license preserved' test -f "$TARGET/UPSTREAM-LICENSE"
assert 'metadata commit' grep -q "$COMMIT" "$TARGET/upstream-source.json"
assert 'metadata repository' grep -Fq "\"repository\": \"$UPSTREAM\"" "$TARGET/upstream-source.json"
assert 'metadata subdirectory' grep -Fq '"subdirectory": "asset-manager"' "$TARGET/upstream-source.json"
assert 'license metadata' grep -Fq '"licenseFileFound": true' "$TARGET/upstream-source.json"
for name in LICENSE NOTICE.md license-MIT.txt COPYRIGHT; do
    assert "notice bytes preserved: $name" cmp "$UPSTREAM/$name" "$TARGET/UPSTREAM-$name"
done
for name in pom.xml mvnw .gitignore .mvn/wrapper/maven-wrapper.properties web/test worker/test; do
    assert "source bytes unchanged: $name" cmp "$UPSTREAM/asset-manager/$name" "$TARGET/$name"
done
assert 'download has no nested Git directory' test ! -e "$TARGET/.git"
assert 'download uses workshop Git root' test "$(git -C "$TARGET" rev-parse --show-prefix)" = ".test-output/${TEMPORARY##*/}/download with spaces/"
if safe_destination "$TARGET" "$ROOT" >/dev/null 2>&1; then exit 1; else PASSED=$((PASSED + 1)); fi
for name in upstream-source.json UPSTREAM-NOTICE.md; do
    printf 'preserve upstream content\n' > "$UPSTREAM/asset-manager/$name"
    git -C "$UPSTREAM" add .
    git -C "$UPSTREAM" -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m $'Fixture collision\n\nCo-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>'
    collision_commit=$(git -C "$UPSTREAM" rev-parse HEAD)
    if bash -c 'source "$1/scripts/download-sample.sh"; download_sample "$2" "$3" "$4" asset-manager java "$1"' _ "$ROOT" "$TEMPORARY/$name" "$UPSTREAM" "$collision_commit"; then
        printf 'FAILED: source collision accepted: %s\n' "$name" >&2; exit 1
    else PASSED=$((PASSED + 1)); fi
    assert "collision not published: $name" test ! -e "$TEMPORARY/$name"
    rm -- "$UPSTREAM/asset-manager/$name"
done

# Failures run in a separate shell so Bash conditional calls cannot disable errexit.
if bash -c 'source "$1/scripts/download-sample.sh"; download_sample "$2" "$3" "$4" asset-manager java "$1"' _ "$ROOT" "$TEMPORARY/failed" "$UPSTREAM" 0000000000000000000000000000000000000000; then
    printf 'FAILED: bad commit accepted\n' >&2; exit 1
else PASSED=$((PASSED + 1)); fi
assert 'failed download not published' test ! -e "$TEMPORARY/failed"
for staging in "$TEMPORARY"/.workshop-download.*; do
    assert 'temporary paths cleaned' test ! -e "$staging"
done
bash "$ROOT/tests/java-deployment.tests.sh"
printf 'PASS: %s Bash assertions\n' "$PASSED"
