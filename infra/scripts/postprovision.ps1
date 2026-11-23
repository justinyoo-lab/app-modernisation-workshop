Write-Host ('Resource group: ' + $env:AZURE_RESOURCE_GROUP)
Write-Host ('VM: ' + $env:AZURE_VM_NAME)
Write-Host 'Connect: Azure portal > VM > Connect > Bastion'
Write-Host 'Sign in with .\appmoduser and the password you entered.'
Write-Host 'In an administrator Windows PowerShell terminal inside the VM:'
Write-Host '  powershell.exe -NoProfile -File "$HOME\scripts\install-vm-tools.ps1"'
Write-Host 'Tools are NOT installed yet. Approve each installation and restart manually when requested.'
Write-Host 'See infra/README.md for installation, verification and resource cleanup.'
