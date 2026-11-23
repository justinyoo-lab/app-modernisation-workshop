. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\install-prerequisites.ps1') -Track dotnet
$script:Passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}

$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\install-prerequisites.ps1'), [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'PowerShell syntax'

if ($IsWindows) {
    function Test-WorkshopBootstrapInteractive { return $true }
    $script:InstallCalls = [Collections.Generic.List[string]]::new()
    $script:Approved = $false
    $script:NodeSuccess = $true
    $script:NodeUpdates = [Collections.Generic.List[bool]]::new()
    $script:SdkText = '10.0.100 [C:\fixture\sdk]'
    $script:SdkCode = 0
    $script:HasWinget = $true
    $script:SdkVersions = "10.0.100`n11.0.100`n10.0.200-preview.1"
    $script:SdkLookupCode = 0
    function Invoke-ToolProbe {
        param($Name, $Arguments)
        if ($Name -eq 'winget') { return [pscustomobject]@{ Code=$script:SdkLookupCode; Text=$script:SdkVersions } }
        return [pscustomobject]@{ Code=$script:SdkCode; Text=$script:SdkText }
    }
    function Install-WorkshopNode { param([switch]$Update); $script:NodeUpdates.Add([bool]$Update); return $script:NodeSuccess }
    function Install-WorkshopJava { param($Major, [switch]$Update); return $true }
    function Get-Command {
        [CmdletBinding()]param($Name, $CommandType)
        if (($Name -eq 'winget' -and $script:HasWinget) -or $Name -eq 'az') { return [pscustomobject]@{ Source="fixture-$Name" } }
    }
    function Confirm-ToolInstall { param($Description); return $script:Approved }
    function winget { $script:InstallCalls.Add(($args -join ' ')); Write-Output 'installer progress'; $global:LASTEXITCODE=0 }
    function Update-ProcessPath { }
    Assert-True (Install-WindowsTools dotnet) 'declining succeeds without installer failure'
    Assert-True ($script:InstallCalls.Count -eq 0) 'declined tools never installed'
    $script:Approved = $true
    Assert-True (Install-WindowsTools dotnet) 'approved installations succeed'
    Assert-True ($script:InstallCalls.Count -eq 3) 'only missing Azure, gh and Modernize tools installed'
    Assert-True ($script:InstallCalls -contains 'install --id GitHub.cli --exact --source winget') 'gh package selected'
    Assert-True ($script:InstallCalls -contains 'install --id GitHub.Copilot.modernization.agent --exact --source winget') 'Modernize package selected'
    Assert-True (@($script:InstallCalls | Where-Object { $_ -like '*OpenJS.NodeJS.LTS*' }).Count -eq 0) 'standalone Node package never selected'
    Assert-True ($script:NodeUpdates.Count -eq 2 -and -not $script:NodeUpdates[0]) '.NET Node uses shared nvm installer without update by default'
    Assert-True (@($script:InstallCalls | Where-Object { $_ -like '*Microsoft.Azd*' }).Count -eq 1) 'azd package selected'
    Assert-True (@($script:InstallCalls | Where-Object { $_ -like '*Microsoft.AzureCLI*' }).Count -eq 0) 'existing Azure CLI skipped'
    $Update = $true
    Assert-True (Install-WindowsTools dotnet) '.NET update succeeds'
    Assert-True ($script:NodeUpdates[2]) '.NET forwards update to nvm'
    Assert-True (Install-WindowsTools java) 'Java uses same nvm installer'
    Assert-True ($script:NodeUpdates[3]) 'Java forwards update to nvm'
    $script:NodeSuccess = $false
    Assert-True (-not (Install-WindowsTools dotnet)) '.NET nvm failure propagates'
    Assert-True (@($script:InstallCalls | Where-Object { $_ -like '*Microsoft.Azd*' }).Count -eq 4) 'Node failure does not block independent missing Azure tools'
    $script:NodeSuccess = $true
    function winget { $global:LASTEXITCODE=1 }
    Assert-True (-not (Install-WindowsTools dotnet)) 'installer failure propagates'
    $script:InstallCalls.Clear()
    $script:Approved = $true
    Assert-True (Install-WorkshopDotnetSdk) 'existing stable SDK succeeds'
    Assert-True ($script:InstallCalls.Count -eq 0) 'existing stable SDK never installed or updated'
    $script:SdkText = "8.0.100 [C:\fixture\sdk]`n10.0.100-preview.1 [C:\fixture\sdk]"
    $script:Approved = $false
    Assert-True (Install-WorkshopDotnetSdk) 'SDK decline leaves validation to final prerequisite check'
    Assert-True ($script:InstallCalls.Count -eq 0) 'declined SDK never installed'
    $script:Approved = $true
    Assert-True (-not (Install-WorkshopDotnetSdk)) 'SDK winget failure propagates'
    function winget {
        $script:InstallCalls.Add(($args -join ' '))
        $global:LASTEXITCODE = 0
    }
    Assert-True (-not (Install-WorkshopDotnetSdk)) 'winget success without stable SDK fails verification'
    function winget {
        $script:InstallCalls.Add(($args -join ' '))
        $script:SdkText += "`n10.0.100 [C:\fixture\sdk]"
        $script:SdkCode = 0
        $global:LASTEXITCODE = 0
    }
    Assert-True (Install-WorkshopDotnetSdk) 'stable SDK installs alongside older and preview SDKs'
    Assert-True ($script:InstallCalls[-1] -eq 'install --id Microsoft.DotNet.SDK.10 --exact --source winget') 'exact SDK package installed without removing existing SDKs'
    $script:SdkText = ''
    Assert-True (Install-WorkshopDotnetSdk) 'runtime-only installation receives SDK'
    $script:SdkText = 'dotnet missing'
    $script:SdkCode = 127
    Assert-True (Install-WorkshopDotnetSdk) 'missing dotnet receives SDK'
    $before = $script:InstallCalls.Count
    $script:SdkText = ''
    Assert-True (Install-WindowsTools java) 'Java does not require SDK'
    Assert-True (@($script:InstallCalls | Select-Object -Skip $before | Where-Object { $_ -like '*Microsoft.DotNet.SDK*' }).Count -eq 0) 'Java never installs SDK'
    $before = $script:InstallCalls.Count
    $script:HasWinget = $false
    Assert-True (Install-WorkshopDotnetSdk) 'missing winget leaves SDK installation manual'
    Assert-True ($script:InstallCalls.Count -eq $before) 'missing winget never launches installer'
    $script:HasWinget = $true
    $script:SdkText = "8.0.100 [C:\fixture\sdk]`n10.0.100 [C:\fixture\sdk]"
    $script:SdkVersions = "11.0.100`n10.0.200-preview.1`n10.0.200`n10.0.99"
    $script:Approved = $false
    Assert-True (Install-WorkshopDotnetSdk -Update) 'SDK update decline succeeds'
    Assert-True ($script:InstallCalls.Count -eq $before) 'declined SDK update never installs'
    $script:Approved = $true
    function winget {
        $script:InstallCalls.Add(($args -join ' '))
        $script:SdkText += "`n10.0.200 [C:\fixture\sdk]"
        $global:LASTEXITCODE = 0
    }
    Assert-True (Install-WorkshopDotnetSdk -Update) 'lower stable SDK updates'
    Assert-True ($script:InstallCalls[-1] -eq 'install --id Microsoft.DotNet.SDK.10 --exact --source winget --version 10.0.200') 'update selects latest numeric stable 10.x only'
    $before = $script:InstallCalls.Count
    Assert-True (Install-WorkshopDotnetSdk -Update) 'current SDK skips update'
    $script:SdkText = '10.0.300 [C:\fixture\sdk]'
    Assert-True (Install-WorkshopDotnetSdk -Update) 'newer local SDK never downgraded'
    Assert-True ($script:InstallCalls.Count -eq $before) 'current and newer SDK never installed'
    $script:SdkLookupCode = 1
    Assert-True (Install-WorkshopDotnetSdk) 'default existing SDK never queries release metadata'
    Assert-True (-not (Install-WorkshopDotnetSdk -Update)) 'SDK lookup failure propagates'
    $script:SdkLookupCode = 0
    $script:SdkVersions = "11.0.100`n10.0.200-preview.1"
    Assert-True (-not (Install-WorkshopDotnetSdk -Update)) 'missing stable 10.x metadata rejected'
    $script:SdkVersions = '10.0.400'
    $script:SdkText = ''
    function winget {
        $script:InstallCalls.Add(($args -join ' '))
        $script:SdkText = '10.0.400 [C:\fixture\sdk]'
        $global:LASTEXITCODE = 0
    }
    Assert-True (Install-WorkshopDotnetSdk -Update) 'missing SDK update pins latest stable release'
    $before = $script:InstallCalls.Count
    $script:SdkText = '10.0.300 [C:\fixture\sdk]'
    function winget { $global:LASTEXITCODE = 1 }
    Assert-True (-not (Install-WorkshopDotnetSdk -Update)) 'SDK update installation failure propagates'
    function winget { $global:LASTEXITCODE = 0 }
    Assert-True (-not (Install-WorkshopDotnetSdk -Update)) 'SDK update verifies exact requested version'
    function Test-WorkshopBootstrapInteractive { return $false }
    Assert-True (-not (Install-WorkshopDotnetSdk -Update)) 'noninteractive SDK installation rejected'
    Assert-True ($script:InstallCalls.Count -eq $before) 'noninteractive SDK never installed'
    function Test-WorkshopBootstrapInteractive { return $true }
    Remove-Item Function:\Invoke-ToolProbe
    foreach ($name in @('Get-Command','Confirm-ToolInstall','winget','Update-ProcessPath','Install-WorkshopNode','Install-WorkshopJava')) { Remove-Item "Function:\$name" }
    $Update = $false
    $Track = 'dotnet'
    $script:PreparationSuccess = $true
    $script:ToolsSuccess = $true
    $script:MainCalls = [Collections.Generic.List[string]]::new()
    function Install-WindowsTools { $script:MainCalls.Add('install'); return $script:ToolsSuccess }
    function Initialize-AzureEnvironment { $script:MainCalls.Add('prepare'); return $script:PreparationSuccess }
    function Write-WorkshopMessage {
        param([string]$Message)
        if ($Message -ceq '[INFO] Running read-only prerequisite checks from ./scripts/check-prerequisites.ps1. Verify MANUAL items yourself.') {
            $script:MainCalls.Add('announce-check')
        }
    }
    function Invoke-PrerequisiteMain { $script:MainCalls.Add('check'); return 0 }
    function Invoke-ToolProbe { return [pscustomobject]@{ Code = 0; Text = 'v22.0.0' } }
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 0) '.NET preparation and final check succeed'
    Assert-True (($script:MainCalls -join ',') -eq 'install,prepare,announce-check,check') '.NET final check is announced after preparation and before execution'
    $script:MainCalls.Clear()
    $script:PreparationSuccess = $false
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1) 'Azure preparation failure survives successful final check'
    Assert-True (($script:MainCalls -join ',') -eq 'install,prepare,announce-check,check') 'final check is still announced when Azure preparation fails'
    $script:MainCalls.Clear()
    $script:ToolsSuccess = $false
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1) 'tool failure prevents preparation'
    Assert-True (($script:MainCalls -join ',') -eq 'install') 'failed tool setup skips Azure actions and probes'
    $script:MainCalls.Clear()
    $script:ToolsSuccess = $true
    $script:PreparationSuccess = $true
    $Track = 'java'
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 0) 'native Java preparation and final check succeed'
    Assert-True (($script:MainCalls -join ',') -eq 'install,prepare,announce-check,check') 'native Java announces the final check before execution'
    foreach ($name in @('Install-WindowsTools','Initialize-AzureEnvironment','Invoke-PrerequisiteMain','Invoke-ToolProbe','Write-WorkshopMessage')) { Remove-Item "Function:\$name" }
    . (Join-Path $root 'scripts\powershell-bootstrap.ps1')
}

$savedCI = $env:CI
try {
    $env:CI='1'
    $Track='dotnet'
    if ($IsWindows) { Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1) 'CI installation rejected' }
}
finally { $env:CI=$savedCI }
Write-Host "PASS: $script:Passed installation PowerShell assertions"
