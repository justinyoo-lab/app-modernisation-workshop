#!/usr/bin/env bash
set -euo pipefail

printf 'Resource group: %s\n' "${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP is required}"
printf 'VM: %s\n' "${AZURE_VM_NAME:?AZURE_VM_NAME is required}"
printf '%s\n' \
    'Connect: Azure portal > VM > Connect > Bastion' \
    'Sign in with .\appmoduser and the password you entered.' \
    'In an administrator Windows PowerShell terminal inside the VM:' \
    '  powershell.exe -NoProfile -File "$HOME\scripts\install-vm-tools.ps1"' \
    'Tools are NOT installed yet. Approve each installation and restart manually when requested.' \
    'See infra/README.md for installation, verification and resource cleanup.'
