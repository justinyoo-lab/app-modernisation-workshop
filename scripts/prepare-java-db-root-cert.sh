#!/usr/bin/env bash
SCRIPT_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIRECTORY/terminal-output.sh"
source "$SCRIPT_DIRECTORY/java-deployment.sh"
jd_main certificate "$@"
