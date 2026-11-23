[CmdletBinding()]
param([switch]$Help)
. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
if ($MyInvocation.InvocationName -eq '.') { throw 'Execute this helper; do not dot-source it.' }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Preserve stdout when the parent captures the returned certificate path.
    $state = Get-WorkshopHostPrerequisites
    if (-not $state.PowerShell) {
        [Console]::Error.WriteLine('[FAIL] PowerShell 7 is required on Windows. No workshop actions were performed. Install Microsoft.PowerShell, then retry.')
        exit 1
    }
    $workerArguments = @('-NoLogo', '-NoProfile', '-File', $PSCommandPath)
    if ($Help) { $workerArguments += '-Help' }
    & $state.PowerShell @workerArguments @args
    exit $LASTEXITCODE
}
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args
if ($bootstrap.Handled) { exit $bootstrap.Code }
. (Join-Path $PSScriptRoot 'java-deployment.ps1')
try { Invoke-JavaDeployment certificate -Help:$Help -RemainingArguments $args }
catch { Write-JavaDeploymentMessage FAIL $_.Exception.Message; exit 1 }
exit 0
