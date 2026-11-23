. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\install-prerequisites.ps1')
$script:CheckResults = [Collections.Generic.List[object]]::new()
$script:Calls = [Collections.Generic.List[string]]::new()
$script:Approved = $false
$script:LoggedIn = $false
$script:Selected = 'id-two'
$script:ActionFails = $false
function Assert-Action([bool]$Condition) { if (-not $Condition) { throw 'Azure action assertion failed' } }
function Test-AzurePrompt { return $true }
function Confirm-AzureAction { return $script:Approved }
function Read-Host { return $script:Selected }
function Invoke-ToolProbe {
    param([string]$Name, [string[]]$Arguments)
    $text = ''; $code = 0
    switch ("$Name $($Arguments -join ' ')") {
        'az account show --query state --output tsv' {
            if ($script:LoggedIn) { $text = 'Enabled' } else { $code = 1; $text = 'fixture auth error' }
        }
        'az account list --query [].[id,name] --output tsv' { $text = "id-one`tFirst`nid-two`tSecond" }
        'az extension show --name containerapp --query version --output tsv' { $code = 1 }
        'azd auth login --check-status' { $code = 1 }
        default { throw "Unexpected probe: $Name $Arguments" }
    }
    return [pscustomobject]@{ Code = $code; Text = $text }
}
function Invoke-AzureAction {
    param([string]$Name, [string[]]$Arguments)
    $script:Calls.Add("$Name $($Arguments -join ' ')")
    $script:LoggedIn = $true
    return -not $script:ActionFails
}
Initialize-AzureAccount
Initialize-ContainerappExtension
Initialize-AzdLogin
Assert-Action ($script:Calls.Count -eq 0)
$script:Approved = $true
Initialize-AzureAccount
Assert-Action (($script:Calls -join ';') -eq 'az login;az account set --subscription id-two')
$script:Calls.Clear()
$script:Selected = 'invalid'
Initialize-AzureAccount
Assert-Action ($script:Calls.Count -eq 0)
Initialize-ContainerappExtension
Initialize-AzdLogin
Assert-Action (($script:Calls -join ';') -eq 'az extension add --name containerapp --upgrade;azd auth login')
$script:Calls.Clear()
$script:ActionFails = $true
$script:LoggedIn = $false
Initialize-AzureAccount
Assert-Action (($script:Calls -join ';') -eq 'az login')
$script:Calls.Clear()
function Test-AzurePrompt { return $false }
Initialize-AzureAccount
Initialize-ContainerappExtension
Initialize-AzdLogin
Initialize-AzureProvider Microsoft.App
Assert-Action ($script:Calls.Count -eq 0)
Remove-Item Function:\Read-Host
. (Join-Path $PSScriptRoot '..\scripts\install-prerequisites.ps1')
function Test-AzurePrompt { return $true }
function Confirm-AzureAction { return $script:Approved }
$script:Registered = $false
$script:QueryFails = $false
$script:Approved = $true
function Invoke-ToolProbe {
    param([string]$Name, [string[]]$Arguments)
    return [pscustomobject]@{
        Code = $(if ($script:QueryFails) { 1 } else { 0 })
        Text = $(if ($script:Registered) { 'Registered' } else { 'NotRegistered' })
    }
}
function Invoke-AzureAction {
    param([string]$Name, [string[]]$Arguments)
    $script:Calls.Add("$Name $($Arguments -join ' ')")
    $script:Registered = $true
    return $true
}
Initialize-AzureProvider Microsoft.App
Assert-Action (($script:Calls -join ';') -eq 'az provider register --namespace Microsoft.App --wait')
$script:Calls.Clear()
Initialize-AzureProvider Microsoft.App
Assert-Action ($script:Calls.Count -eq 0)
$script:Registered = $false
$script:QueryFails = $true
Initialize-AzureProvider Microsoft.App
Assert-Action ($script:Calls.Count -eq 0)
Assert-Action ($script:CheckResults[-1].Status -eq 'FAIL')
$script:QueryFails = $false
$script:Approved = $false
Initialize-AzureProvider Microsoft.App
Assert-Action ($script:Calls.Count -eq 0)
. (Join-Path $PSScriptRoot '..\scripts\install-prerequisites.ps1')
$savedCI = $env:CI
try {
    $env:CI = '1'
    Assert-Action (-not (Confirm-AzureAction 'must not prompt'))
}
finally { $env:CI = $savedCI }
$script:Calls.Clear()
function Initialize-AzureAccount { $script:Calls.Add('account') }
function Initialize-ContainerappExtension { $script:Calls.Add('extension') }
function Initialize-AzdLogin { $script:Calls.Add('azd') }
function Show-AzureIdentity { $script:Calls.Add('identity') }
function Initialize-AzureProvider { param($Provider); $script:Calls.Add($Provider) }
function Invoke-ToolProbe {
    Assert-Action ($env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL -eq 'no')
    return [pscustomobject]@{ Code = 0; Text = 'Enabled' }
}
$savedDynamic = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
try {
    $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'yes_prompt'
    Assert-Action (Initialize-AzureEnvironment)
    Assert-Action ($env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL -eq 'yes_prompt')
    Assert-Action (($script:Calls -join ';') -eq 'account;extension;identity;Microsoft.App;Microsoft.OperationalInsights;Microsoft.Storage;Microsoft.ContainerRegistry;Microsoft.ServiceBus;Microsoft.Sql;azd')
    $script:Calls.Clear()
    Assert-Action (Initialize-AzureEnvironment -SelectedTrack java)
    Assert-Action ($script:Calls -contains 'Microsoft.DBforPostgreSQL' -and $script:Calls -notcontains 'Microsoft.Sql')
    $script:Calls.Clear()
    function Invoke-ToolProbe { return [pscustomobject]@{ Code = 1; Text = 'auth error' } }
    Assert-Action (Initialize-AzureEnvironment)
    Assert-Action ($script:Calls.Count -eq 0)
    function Invoke-ToolProbe { return [pscustomobject]@{ Code = 0; Text = 'Enabled' } }
    function Initialize-AzureAccount { Add-Check FAIL 'azure-action' 'fixture failure' }
    Assert-Action (-not (Initialize-AzureEnvironment))
}
finally { $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = $savedDynamic }
function Confirm-AzureAction { throw 'Read-only checks must not prompt' }
function Initialize-AzureAccount { throw 'Read-only checks must not prepare accounts' }
function Initialize-ContainerappExtension { throw 'Read-only checks must not install extensions' }
function Initialize-AzdLogin { throw 'Read-only checks must not log in' }
function Invoke-AzureAction { throw 'Read-only checks must not mutate Azure' }
function Test-ContainerRuntime { }
function Show-AzureIdentity { }
function Invoke-ToolProbe {
    param([string]$Name, [string[]]$Arguments)
    $code = 0; $text = ''
    switch -Wildcard ("$Name $($Arguments -join ' ')") {
        'git --version' { $text = 'git version 2.0.0' }
        'node --version' { $text = 'v22.0.0' }
        'modernize --version' { $text = '1.0.95' }
        'gh --version' { $text = 'gh version 2.45.0' }
        'gh auth status' { $text = 'fixture signed in' }
        'az version --output json' { $text = '{}' }
        'az extension show *' { $code = 1 }
        'az account show --query state --output tsv' { $text = 'Enabled' }
        'az provider show *' { $text = 'NotRegistered' }
        'azd version' { $text = 'azd version 1.37.3' }
        'azd auth login --check-status' { $code = 1 }
        default { throw "Unexpected read-only probe: $Name $Arguments" }
    }
    return [pscustomobject]@{ Code = $code; Text = $text }
}
$script:CheckResults.Clear()
Test-CommonTools docker dotnet
Assert-Action (@($script:CheckResults | Where-Object Status -eq FAIL).Count -eq 8)
function Invoke-ToolProbe { return [pscustomobject]@{ Code = 0; Text = 'Registered' } }
Test-AzureProvider Microsoft.App
Assert-Action ($script:CheckResults[-1].Status -eq 'PASS')
Write-Host 'PASS: Azure action approval, selection, failure and noninteractive cases'
