#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    printf '%s\n' '[FAIL] Usage: preprovision.sh [output-path]' >&2
    exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
target="${1:-$SCRIPT_DIR/../.generated/payload.json}"
work=''
trap 'if [[ -n "$work" ]]; then rm -rf -- "$work"; fi' EXIT
trap 'printf "%s\n" "[FAIL] VM script packaging failed." >&2' ERR

mkdir -p -- "$(dirname -- "$target")"
work="$(mktemp -d "$(dirname -- "$target")/.payload.XXXXXX")"

names=(
    powershell-bootstrap.ps1 install-prerequisites.ps1 windows-prerequisite-updates.ps1
    check-prerequisites.ps1 dotnet-framework-tools.ps1 java-tools.ps1
    install-vm-tools.ps1 buildtools.vsconfig
)
printf '{"schemaVersion":1,"files":[' > "$work/files.json"
separator=''
for name in "${names[@]}"; do
    case "$name" in
        install-vm-tools.ps1|*.vsconfig) source="$SCRIPT_DIR/$name" ;;
        *) source="$ROOT/scripts/$name" ;;
    esac
    printf '%s{"name":"%s","content":"' "$separator" "$name" >> "$work/files.json"
    base64 < "$source" | tr -d '\r\n' >> "$work/files.json"
    printf '"}' >> "$work/files.json"
    separator=','
done
printf ']}' >> "$work/files.json"

if [[ $(wc -c < "$work/files.json") -gt 1048576 ]]; then
    printf '%s\n' '[FAIL] VM script payload exceeds the 1 MiB uncompressed limit.' >&2
    exit 1
fi
gzip -c < "$work/files.json" | base64 | tr -d '\r\n' > "$work/content"
length="$(wc -c < "$work/content" | tr -d '[:space:]')"
if [[ "$length" -gt 90000 ]]; then
    printf '%s\n' '[FAIL] Compressed VM payload is too large for inline delivery.' >&2
    exit 1
fi
{
    printf '{"content":"'
    cat "$work/content"
    printf '"}\n'
} > "$work/payload.json"
mv -f -- "$work/payload.json" "$target"
printf '[PASS] VM script payload: %s base64 characters.\n' "$length"
