[CmdletBinding()]
param([string]$SqlPath, [switch]$Help)
. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
if ($MyInvocation.InvocationName -eq '.') { throw 'Execute this helper; do not dot-source it.' }
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args
if ($bootstrap.Handled) { exit $bootstrap.Code }
. (Join-Path $PSScriptRoot 'java-deployment.ps1')
try { Invoke-JavaDeployment schema $SqlPath -Help:$Help -RemainingArguments $args }
catch { Write-JavaDeploymentMessage FAIL $_.Exception.Message; exit 1 }
exit 0
