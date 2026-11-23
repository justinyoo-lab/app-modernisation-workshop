. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\install-prerequisites.ps1') -Track java
$realUpdatePath = ${function:Update-ProcessPath}
$script:Passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}
foreach ($file in @('install-prerequisites.ps1', 'windows-prerequisite-updates.ps1')) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root "scripts\$file"), [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "$file syntax"
}
if (-not $IsWindows) { Write-Host "PASS: $script:Passed assertions (Windows mocks skipped)"; exit 0 }

$savedHome = $env:NVM_HOME; $savedLink = $env:NVM_SYMLINK; $savedPath = $env:PATH
try {
    $env:NVM_HOME = 'C:\fixture-nvm'
    $env:NVM_SYMLINK = 'C:\fixture-node'
    function Reset-Fixture {
        $script:Calls = [Collections.Generic.List[string]]::new()
        $script:Approvals = [Collections.Generic.Queue[bool]]::new()
        $script:Prompts = [Collections.Generic.List[string]]::new()
        $script:Interactive = $true
        $script:HasNvm = $true; $script:HasNode = $true; $script:HasWinget = $true
        $script:NvmSource = 'C:\fixture-nvm\nvm.exe'
        $script:Current = '22.1.0'; $script:Latest = [version]'22.9.0'
        $script:Owned = $true; $script:ExistingRelease = $false
        $script:InstallCode = 0; $script:UseCode = 0; $script:InstalledVersion = '22.9.0'
        $script:Activate = $true; $script:Refreshes = 0; $script:FailLookup = $false
        $script:ConcurrentVersion = $null
        $script:NvmVersion = '1.2.2'; $script:NvmMode = 'shim'
        $script:NvmAutoInstall = $false; $script:NvmEnabled = $true; $script:NvmDefault = $true
        $script:NvmList = $null; $script:NvmListCode = 0
        $script:FirstActivationVersion = $null
        $script:NodeProbeCode = 0
        $script:JavaSuccess = $true
        $script:Managed = [pscustomobject]@{ Path = 'C:\PowerShell\7\pwsh.exe'; Version = [version]'7.5.0' }
        $script:Show = "버전`n----`n7.5.1`n7.5.0`n7.6.0-preview.1"; $script:ShowCode = 0; $script:WorkerFail = $false
    }
    function Get-Command {
        [CmdletBinding()]param($Name, $CommandType, [switch]$All)
        if ($Name -eq 'node' -and $script:HasNode) { return [pscustomobject]@{ Source='C:\fixture-node\node.exe' } }
        if ($Name -eq 'nvm' -and $script:HasNvm) { return [pscustomobject]@{ Source=$script:NvmSource } }
        if ($Name -eq 'winget' -and $script:HasWinget) { return [pscustomobject]@{ Source='C:\fixture-winget.exe' } }
    }
    function Test-WorkshopBootstrapInteractive { return $script:Interactive }
    function Confirm-ToolInstall {
        param($Description)
        $script:Prompts.Add($Description)
        if ($script:Approvals.Count) { return $script:Approvals.Dequeue() }
        return $true
    }
    function Update-ProcessPath { $script:Refreshes++ }
    function Test-WorkshopNvmOwnership { param($NodePath); return $script:Owned }
    function Get-WorkshopNodeRelease {
        param($Major)
        $script:Calls.Add("release $Major")
        if ($script:FailLookup) { throw 'fixture lookup failure' }
        return $script:Latest
    }
    function Test-Path {
        [CmdletBinding()]param($LiteralPath, $PathType)
        if ($LiteralPath -like '*\v*\node.exe') { return $script:ExistingRelease }
        return $false
    }
    function winget {
        $script:Calls.Add("winget $($args -join ' ')")
        $global:LASTEXITCODE = $script:InstallCode
        if ($script:InstallCode -eq 0) {
            $script:HasNvm = $true
            $env:NVM_HOME = 'C:\fixture-nvm'; $env:NVM_SYMLINK = 'C:\fixture-node'
        }
    }
    function Invoke-ToolProbe {
        param($Name, $Arguments)
        $operation = "$Name $($Arguments -join ' ')"
        $script:Calls.Add($operation)
        $code = 0; $text = ''
        if ($Name -eq 'node') { $text = "v$script:Current"; $code = $script:NodeProbeCode }
        elseif ($Name -eq 'dotnet') { $text = '10.0.100 [C:\fixture\sdk]' }
        elseif ($Name -like '*\v*\node.exe') { $text = "v$script:InstalledVersion" }
        elseif ($Name -eq 'nvm' -and $Arguments[0] -eq 'version') { $text = $script:NvmVersion }
        elseif ($Name -eq 'nvm' -and $Arguments[0] -eq 'config') {
            $text = @{ root='C:\fixture-data\installs'; mode=$script:NvmMode; auto_install=$script:NvmAutoInstall; enabled=$script:NvmEnabled } | ConvertTo-Json
        }
        elseif ($Name -eq 'nvm' -and $Arguments[0] -eq 'list') {
            $code = $script:NvmListCode
            $text = if ($null -ne $script:NvmList) { $script:NvmList } elseif ($script:NvmDefault) {
                '[{"version":"' + $script:Current + '","installed":true,"default":true}]'
            } else { '[]' }
        }
        elseif ($Name -eq 'nvm' -and $Arguments[0] -eq 'install') {
            $code = $script:InstallCode
            if ($script:ConcurrentVersion) { $script:Current = $script:ConcurrentVersion }
            if ($code -eq 0 -and $script:FirstActivationVersion) {
                $script:HasNode=$true; $script:Current=$script:FirstActivationVersion; $script:NodeProbeCode=0
                $script:NvmDefault=$true; $script:NvmList=$null
            }
        }
        elseif ($Name -eq 'nvm' -and $Arguments[0] -eq 'use') {
            $code = $script:UseCode
            if ($script:Activate -and $code -eq 0) { $script:HasNode = $true; $script:Current = $script:InstalledVersion; $script:NodeProbeCode = 0 }
        }
        elseif ($Name -eq 'winget' -and $Arguments -contains 'Microsoft.DotNet.SDK.10') { $text = '10.0.100' }
        elseif ($Name -eq 'winget') { $text = $script:Show; $code = $script:ShowCode }
        return [pscustomobject]@{ Code=$code; Text=$text }
    }
    function Install-WorkshopJava {
        param([int]$Major, [switch]$Update)
        $script:Calls.Add("java $Major update=$([bool]$Update)")
        return $script:JavaSuccess
    }
    function Get-WorkshopManagedPowerShell { return $script:Managed }
    function Start-WorkshopPowerShellUpdate {
        param($Executable, $Version)
        if ($script:WorkerFail) { throw 'fixture worker failure' }
        $script:Calls.Add("worker $Executable $Version")
    }

    Reset-Fixture
    Assert-True (Install-WorkshopNode) 'default preserves managed current Node'
    Assert-True ($script:Calls.Count -eq 2 -and $script:Prompts.Count -eq 0) 'default only verifies nvm and current Node'
    Reset-Fixture; $script:Approvals.Enqueue($false)
    Assert-True (Install-WorkshopNode -Update) 'decline update preserves supported Node'
    Assert-True ($script:Calls -contains 'release 22' -and
        $script:Calls -notcontains 'nvm install 22.9.0' -and $script:Calls -notcontains 'nvm use 22.9.0') 'decline follows read-only lookup without installing or activating'
    Reset-Fixture
    Assert-True (Install-WorkshopNode -Update) 'installs and activates latest same major'
    Assert-True ($script:Calls -contains 'release 22' -and $script:Calls -contains 'nvm install 22.9.0' -and $script:Calls -contains 'nvm use 22.9.0') 'exact nvm commands'
    Assert-True ($script:Prompts.Count -eq 2 -and $script:Refreshes -eq 2) 'separate install activation consent and PATH refresh'
    Assert-True (@($script:Calls | Where-Object { $_ -match 'uninstall|delete|OpenJS|azd|AzureCLI' }).Count -eq 0) 'no removals or unrelated tools'
    Assert-True (Install-WorkshopNode -Update) 'repeat latest succeeds'
    Assert-True (@($script:Calls | Where-Object { $_ -eq 'nvm install 22.9.0' }).Count -eq 1) 'repeat no reinstall'
    Assert-True ($script:Prompts.Count -eq 2) 'repeat current Node never prompts again'
    Reset-Fixture; $script:Current = '24.1.0'; $script:Latest = [version]'24.9.0'; $script:InstalledVersion = '24.9.0'
    Assert-True (Install-WorkshopNode -Update) 'newer major updated in place'
    Assert-True ($script:Calls -contains 'release 24' -and $script:Calls -notcontains 'release 22') 'never select 22 for active 24'
    Reset-Fixture; $script:Current = '22.10.0'
    Assert-True (Install-WorkshopNode -Update) 'ahead of catalog retained'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0') 'no downgrade'
    Assert-True ($script:Prompts.Count -eq 0) 'newer local Node never prompts'
    Reset-Fixture; $script:Current = '20.19.0'
    Assert-True (Install-WorkshopNode -Update) 'unsupported major moves to 22'
    Reset-Fixture; $script:Current = '20.19.0'
    Assert-True (-not (Install-WorkshopNode)) 'default does not silently update old managed Node'
    Reset-Fixture; $script:HasNode = $false
    Assert-True (Install-WorkshopNode) 'missing Node installs 22 through existing nvm'
    Reset-Fixture; $script:ExistingRelease = $true
    Assert-True (Install-WorkshopNode -Update) 'existing inactive release reused'
    Assert-True ($script:Calls -notcontains 'nvm install 22.9.0') 'no reinstall installed release'
    Assert-True ($script:Prompts.Count -eq 1 -and $script:Prompts[0] -like 'Run nvm use *') 'installed inactive release only asks for activation'
    Reset-Fixture; $script:Approvals.Enqueue($true); $script:Approvals.Enqueue($false)
    Assert-True (Install-WorkshopNode -Update) 'declined activation preserves old supported active version'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0' -and $script:Current -eq '22.1.0') 'activation separately optional'
    Reset-Fixture; $script:InstallCode = 1
    Assert-True (-not (Install-WorkshopNode -Update)) 'nvm install failure'
    Reset-Fixture; $script:UseCode = 1
    Assert-True (-not (Install-WorkshopNode -Update)) 'nvm use failure'
    Reset-Fixture; $script:InstalledVersion = '22.8.0'
    Assert-True (-not (Install-WorkshopNode -Update)) 'wrong installed version fails'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0') 'failed verification never activates'
    Reset-Fixture; $script:Activate = $false
    Assert-True (-not (Install-WorkshopNode -Update)) 'exit zero with unchanged active version fails'
    Reset-Fixture; $script:ConcurrentVersion = '24.1.0'
    Assert-True (-not (Install-WorkshopNode -Update)) 'concurrent active major change remains untouched'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0' -and $script:Current -eq '24.1.0') 'concurrent change never downgraded'
    Reset-Fixture; $script:Current = 'invalid'
    Assert-True (-not (Install-WorkshopNode -Update)) 'invalid active version fails'
    Reset-Fixture; $script:FailLookup = $true
    Assert-True (-not (Install-WorkshopNode -Update)) 'release lookup failure'
    Assert-True ($script:Prompts.Count -eq 0) 'failed release lookup never asks to install'
    Reset-Fixture; $script:Owned = $false
    Assert-True (-not (Install-WorkshopNode -Update)) 'unknown ownership manual'
    Assert-True ($script:Prompts.Count -eq 0) 'unknown ownership never prompts takeover'
    Reset-Fixture; $script:HasNvm = $false
    Assert-True (-not (Install-WorkshopNode -Update)) 'standalone Node blocks nvm installer'
    Assert-True (@($script:Calls | Where-Object { $_ -like 'winget *' }).Count -eq 0) 'no standalone takeover'
    Reset-Fixture; $script:HasNode = $false; $script:HasNvm = $false
    Assert-True (-not (Install-WorkshopNode)) 'unknown nvm environment blocks installer'
    $env:NVM_HOME = ''; $env:NVM_SYMLINK = ''
    Reset-Fixture; $script:HasNode = $false; $script:HasNvm = $false
    Assert-True (Install-WorkshopNode) 'fresh nvm manager and Node install'
    Assert-True ($script:Calls -contains 'winget install --id AuthorSoftware.NVMWindows --exact --source winget') 'verified nvm winget identifier'
    Assert-True ($script:Prompts.Count -eq 3) 'manager install Node install activation separately consented'
    $env:NVM_HOME = ''; $env:NVM_SYMLINK = ''
    Reset-Fixture; $script:HasNode = $false; $script:HasNvm = $false; $script:Approvals.Enqueue($false)
    Assert-True (-not (Install-WorkshopNode)) 'decline manager install'
    Reset-Fixture; $script:HasNode = $false; $script:HasNvm = $false; $script:InstallCode = 1
    Assert-True (-not (Install-WorkshopNode)) 'manager failure propagates'
    Reset-Fixture; $script:Interactive = $false
    Assert-True (-not (Install-WorkshopNode -Update)) 'noninteractive Node rejected'
    Assert-True ($script:Calls.Count -eq 0 -and $script:Prompts.Count -eq 0) 'noninteractive no activity'

    Reset-Fixture
    Assert-True ((Update-WorkshopWindowsHost) -eq 3010) 'PS update requires exit and restart, not success'
    Assert-True ($script:Calls -contains 'worker C:\PowerShell\7\pwsh.exe 7.5.1') 'PowerShell update uses independent worker'
    Assert-True ($script:Prompts.Count -eq 1) 'PowerShell update requires its own consent'
    Reset-Fixture; $script:Approvals.Enqueue($false)
    Assert-True ((Update-WorkshopWindowsHost) -eq 0) 'declined PowerShell update continues'
    Assert-True (@($script:Calls | Where-Object { $_ -like 'worker *' }).Count -eq 0) 'declined host unchanged'
    Reset-Fixture; $script:Managed = $null
    Assert-True ((Update-WorkshopWindowsHost) -eq 0) 'unmanaged PowerShell skips optional update without failure'
    Assert-True (@($script:Calls | Where-Object { $_ -like 'worker *' }).Count -eq 0) 'unknown provenance never schedules replacement'
    Assert-True ($script:Calls.Count -eq 0 -and $script:Prompts.Count -eq 0) 'manual PowerShell update performs no catalog lookup or consent prompt'
    Reset-Fixture; $script:Show = '7.5.0'
    Assert-True ((Update-WorkshopWindowsHost) -eq 0) 'already latest host no worker'
    Assert-True ($script:Prompts.Count -eq 0 -and @($script:Calls | Where-Object { $_ -like 'worker *' }).Count -eq 0) 'current PowerShell never schedules reinstall'
    Reset-Fixture; $script:Show = '8.0.0'
    Assert-True ((Update-WorkshopWindowsHost) -eq 1) 'PS never upgrades to new major'
    Reset-Fixture; $script:ShowCode = 1
    Assert-True ((Update-WorkshopWindowsHost) -eq 1) 'PS catalog failure'
    Reset-Fixture; $script:WorkerFail = $true
    Assert-True ((Update-WorkshopWindowsHost) -eq 1) 'worker launch failure'
    Reset-Fixture; $script:Interactive = $false
    Assert-True ((Update-WorkshopWindowsHost) -eq 1) 'noninteractive host rejected'
    Assert-True ($script:Calls.Count -eq 0 -and $script:Prompts.Count -eq 0) 'noninteractive no host prompts'

    $env:NVM_HOME = 'C:\fixture-nvm'; $env:NVM_SYMLINK = 'C:\fixture-node'
    $Update = $true
    foreach ($selectedTrack in @('java', 'dotnet')) {
        Reset-Fixture
        Assert-True (Install-WindowsTools $selectedTrack) "$selectedTrack installs same-major Node through shared nvm implementation"
        Assert-True ($script:Calls -contains 'nvm install 22.9.0' -and $script:Calls -contains 'nvm use 22.9.0') "$selectedTrack installs and activates with nvm"
        foreach ($package in @('Microsoft.AzureCLI', 'Microsoft.Azd', 'GitHub.cli', 'GitHub.Copilot.modernization.agent')) {
            Assert-True ($script:Calls -contains "winget install --id $package --exact --source winget") "$selectedTrack installs missing $package on Windows"
        }
        if ($selectedTrack -eq 'java') {
            Assert-True ($script:Calls -contains 'java 8 update=True' -and $script:Calls -contains 'java 25 update=True') 'Java installs both JDKs with Update forwarded'
            Assert-True ($script:Calls -notcontains 'dotnet --list-sdks') 'Java never probes the .NET SDK'
        }
        else {
            Assert-True ($script:Calls -contains 'dotnet --list-sdks' -and
                @($script:Calls | Where-Object { $_ -like 'java *' }).Count -eq 0) '.NET checks its SDK without installing JDKs'
        }
    }
    Reset-Fixture; $Update = $false
    Assert-True (Install-WindowsTools java) 'Java default prepares native tools without updates'
    Assert-True ($script:Calls -contains 'java 8 update=False' -and $script:Calls -contains 'java 25 update=False') 'Java default does not request JDK updates'
    Reset-Fixture; $script:JavaSuccess = $false
    Assert-True (-not (Install-WindowsTools java)) 'Java preparation failure is not masked by successful common tools'
    $Update = $true
    Reset-Fixture; $script:Approvals.Enqueue($true); $script:Approvals.Enqueue($false)
    Assert-True (Install-WindowsTools dotnet) '.NET declined activation keeps supported current Node'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0') '.NET activation decline never switches common link'
    foreach ($mode in @('shim', 'link')) {
        Reset-Fixture; $script:NvmVersion = '2.0.1'; $script:NvmMode = $mode
        Assert-True (Install-WorkshopNode -Update) "v2 $mode update succeeds"
        Assert-True ($script:Calls -contains 'C:\fixture-data\installs\v22.9.0\node.exe --version') "v2 $mode uses configured install root"
        Assert-True ($script:Calls -contains 'nvm use 22.9.0 --no-install') "v2 $mode activation never implicitly installs"
    }
    Reset-Fixture; $script:NvmVersion = '2.0.1'; $script:NvmDefault = $false; $script:NodeProbeCode = 1
    Assert-True (Install-WorkshopNode) 'v2 fresh shim without selected runtime can install'
    Assert-True ($script:Calls -contains 'nvm install 22.9.0') 'v2 empty installed list selects 22'
    Reset-Fixture; $script:NvmVersion='2.0.1'; $script:NvmDefault=$false; $script:NodeProbeCode=1
    $script:NvmList='No versions installed.'; $script:FirstActivationVersion='22.9.0'
    Assert-True (Install-WorkshopNode) 'nvm 2.0.1 textual empty list and first-install automatic default selection succeed'
    Assert-True ($script:Prompts.Count -eq 1 -and $script:Prompts[0] -match 'automatically selects.*default' -and
        $script:Calls -notcontains 'nvm use 22.9.0 --no-install') 'first installation obtains activation consent before nvm auto-selects and avoids a redundant switch'
    Reset-Fixture; $script:NvmVersion='2.0.1'; $script:NvmDefault=$false; $script:NodeProbeCode=1
    $script:NvmList='No versions installed.'; $script:Approvals.Enqueue($false)
    Assert-True (-not (Install-WorkshopNode)) 'declining first installation also prevents automatic default selection'
    Assert-True ($script:Calls -notcontains 'nvm install 22.9.0') 'first-install activation cannot precede consent'
    Reset-Fixture; $script:NvmVersion='2.0.1'; $script:NvmDefault=$false; $script:NodeProbeCode=1
    $script:NvmList='No versions installed.'; $script:FirstActivationVersion='24.1.0'
    Assert-True (-not (Install-WorkshopNode)) 'unexpected first-install default selection is not accepted'
    Assert-True ($script:Calls -notcontains 'nvm use 22.9.0 --no-install') 'unexpected default is not overwritten'
    Reset-Fixture; $script:NvmVersion='2.0.1'; $script:NvmDefault=$false; $script:NodeProbeCode=1
    $script:NvmList='No versions installed.'; $script:NvmListCode=1
    Assert-True (-not (Install-WorkshopNode)) 'textual empty list is accepted only with a successful nvm exit'
    Assert-True ($script:Calls -notcontains 'nvm install 22.9.0') 'failed nvm listing never starts installation'
    Reset-Fixture; $script:NvmVersion = '2.0.1'; $script:NvmDefault = $false
    $script:Current = '24.1.0'; $script:Latest = [version]'24.9.0'; $script:InstalledVersion = '24.9.0'
    Assert-True (Install-WorkshopNode -Update) 'v2 detected runtime without default still preserves active major'
    Assert-True ($script:Calls -contains 'release 24') 'v2 detected runtime never downgraded to 22'
    Reset-Fixture; $script:NvmVersion = '2.0.1'; $script:NvmAutoInstall = $true
    Assert-True (-not (Install-WorkshopNode -Update)) 'v2 auto-install requires manual preparation'
    Assert-True ($script:Calls -notcontains 'node --version' -and
        @($script:Calls | Where-Object { $_ -like 'nvm install *' }).Count -eq 0) 'v2 auto-install cannot bypass per-tool consent through shim probes'
    foreach ($badList in @('{}', '[{}]', '[{"version":"bad","installed":true,"default":true}]', '[invalid]', 'unexpected output')) {
        Reset-Fixture; $script:NvmVersion = '2.0.1'; $script:NvmList = $badList
        Assert-True (-not (Install-WorkshopNode -Update)) 'v2 malformed installed list rejected'
    }
    function Update-WorkshopWindowsHost { $script:HostRuns++; return $script:HostCode }
    function Install-WindowsTools { param($SelectedTrack); $script:ToolRuns++; $script:Calls.Add("tools $SelectedTrack"); return $script:ToolSuccess }
    function Initialize-AzureEnvironment {
        param($SelectedTrack = 'dotnet')
        $script:AzureRuns++
        $script:Calls.Add("azure $SelectedTrack")
        return $script:AzureSuccess
    }
    function Invoke-PrerequisiteMain { $script:PrerequisiteRuns++; $script:Calls.Add('check'); return $script:PrerequisiteCode }
    Reset-Fixture; $script:HostRuns = 0; $script:ToolRuns = 0; $script:HostCode = 0
    $script:ToolSuccess = $true; $script:PrerequisiteRuns = 0; $script:PrerequisiteCode = 0
    $script:AzureRuns = 0; $script:AzureSuccess = $true
    $Update = $true; $Track = 'java'
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 0) 'main update then Java verification'
    Assert-True ($script:HostRuns -eq 1 -and $script:ToolRuns -eq 1) 'host update runs once only'
    Assert-True (($script:Calls -join ',') -eq 'tools java,azure java,check') 'Java prepares native tools and track-specific Azure before full prerequisite checks'
    $script:HostCode = 3010
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1 -and $script:ToolRuns -eq 1) 'restart pending stops before tool actions'
    $script:HostCode = 1
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1 -and $script:ToolRuns -eq 2) 'host failure does not block independent tool work or mask failure'
    $Track = 'dotnet'; $script:HostCode = 0
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 0) '.NET host updates keep existing CLI path'
    $Update = $false; $runs = $script:HostRuns
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 0 -and $script:HostRuns -eq $runs) 'default never calls host updater'
    $script:ToolSuccess = $false; $Track = 'java'; $script:Calls.Clear()
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1 -and ($script:Calls -join ',') -eq 'tools java') 'Java preparation failure skips Azure actions and prerequisite probes'
    $Track = 'dotnet'; $prerequisiteRuns = $script:PrerequisiteRuns
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1 -and $script:PrerequisiteRuns -eq $prerequisiteRuns) '.NET preparation failure never reenters potentially auto-installing prerequisite probes'
    $script:ToolSuccess = $true; $Track = 'java'; $script:AzureSuccess = $false
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1) 'Java Azure preparation failure propagates'
    $script:AzureSuccess = $true; $script:PrerequisiteCode = 1
    Assert-True ((Invoke-InstallPrerequisiteMain) -eq 1) 'Java full prerequisite failure propagates'
    $env:PATH = 'C:\fixture-first'
    & $realUpdatePath
    Assert-True (($env:PATH -split ';')[0] -eq 'C:\fixture-first') 'real PATH refresh preserves existing priority'
    foreach ($scope in @('Machine', 'User')) {
        foreach ($directory in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            $expanded = [Environment]::ExpandEnvironmentVariables($directory.Trim())
            if ($expanded) { Assert-True ($expanded -in ($env:PATH -split ';')) "real PATH refresh appends $scope path" }
        }
    }
    $env:PATH = $savedPath

    # Exercise the real read-only ownership and parsing helpers with fake paths.
    . (Join-Path $root 'scripts\windows-prerequisite-updates.ps1')
    $env:NVM_HOME = 'C:\fixture-nvm'; $env:NVM_SYMLINK = 'C:\fixture-node'
    Reset-Fixture
    $script:LinkType = 'SymbolicLink'; $script:Target = 'C:\fixture-nvm\v22.1.0'
    $script:SettingsRoot = 'C:\fixture-nvm'; $script:SettingsPath = 'C:\fixture-node'
    function Get-Content { param($LiteralPath); return @("root: $script:SettingsRoot", "path: $script:SettingsPath") }
    function Get-Item { [CmdletBinding()]param($LiteralPath, [switch]$Force); return [pscustomobject]@{ LinkType=$script:LinkType; Target=$script:Target } }
    function Test-Path { [CmdletBinding()]param($LiteralPath, $PathType); return $true }
    function Invoke-ToolProbe {
        param($Name, $Arguments)
        $text = switch ($Name) {
            nvm {
                if ($Arguments[0] -eq 'config') {
                    @{ root='C:\fixture-data\installs'; mode=$script:NvmMode; auto_install=$script:NvmAutoInstall; enabled=$true } | ConvertTo-Json
                } else { $script:NvmVersion }
            }
            node { 'v22.1.0' }
            winget { $script:WingetText }
            default { '7.5.0' }
        }
        return [pscustomobject]@{ Code=$script:ProbeCode; Text=$text }
    }
    $script:ProbeCode = 0; $script:NvmVersion = '1.2.2'
    Assert-True (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe') 'real ownership helper verified'
    $script:LinkType = 'Junction'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'junction collision rejected'
    $script:LinkType = $null
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'ordinary directory collision rejected'
    $script:LinkType = 'SymbolicLink'; $script:Target = 'C:\other\v22.1.0'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'foreign link rejected'
    $script:Target = 'C:\fixture-nvm\v22.1.0'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\standalone\node.exe')) 'foreign PATH Node rejected'
    $script:SettingsRoot = 'C:\other'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'foreign settings rejected'
    $script:SettingsRoot = 'C:\fixture-nvm'; $script:ProbeCode = 1
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'nvm version error rejected'
    $script:ProbeCode = 0; $script:NvmSource = 'C:\foreign\nvm.exe'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-node\node.exe')) 'foreign nvm executable rejected'
    $script:NvmSource = 'C:\fixture-nvm\nvm.exe'
    $script:NvmVersion = '2.0.1'; $script:NvmMode = 'shim'; $script:NvmAutoInstall = $false
    $script:LinkType = 'Junction'; $script:Target = 'C:\fixture-data\.shim'
    Assert-True (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe') 'v2 real shim ownership accepts managed junction'
    $script:LinkType = $null
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe')) 'v2 ordinary runtime directory collision rejected'
    $script:LinkType = 'Junction'; $script:Target = 'C:\foreign\.shim'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe')) 'v2 foreign shim target rejected'
    $script:Target = 'C:\fixture-data\.shim'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\standalone\node.exe')) 'v2 standalone PATH Node rejected'
    $script:NvmMode = 'link'; $script:Target = 'C:\fixture-data\installs\v22.1.0'
    Assert-True (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe') 'v2 link mode accepts managed version junction'
    $script:Target = 'C:\foreign\v22.1.0'
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe')) 'v2 foreign linked version rejected'
    $script:Target = 'C:\fixture-data\installs\v22.1.0'; $script:NvmAutoInstall = $true
    Assert-True (-not (Test-WorkshopNvmOwnership 'C:\fixture-data\.nodejs\node.exe')) 'v2 ownership gate refuses automatic installation'
    function Invoke-RestMethod { param($Uri); return @(@{ version='v24.9.0' }, @{ version='v22.8.0' }, @{ version='v22.9.0' }, @{ version='v22.10.0-rc.1' }) }
    Assert-True ((Get-WorkshopNodeRelease 22) -eq [version]'22.9.0') 'release index excludes prereleases and other majors'
    Assert-True (-not (Get-WorkshopNodeRelease 26)) 'missing release never fabricated'
    $script:WingetText = 'PowerShell Microsoft.PowerShell 7.5.0 winget'
    function Get-ItemProperty {
        [CmdletBinding()]param([Parameter(Position=0)]$Path)
        return [pscustomobject]@{ Publisher='Microsoft Corporation'; DisplayName='PowerShell 7.5.0-x64'; InstallLocation=$script:PSLocation; DisplayVersion='7.5.0' }
    }
    $script:PSLocation = $PSHOME
    Assert-True ([bool](Get-WorkshopManagedPowerShell)) 'matching MSI registry winget and executable provenance'
    $script:PSLocation = 'C:\foreign'
    Assert-True (-not (Get-WorkshopManagedPowerShell)) 'winget list alone insufficient for provenance'
    $script:PSLocation = $PSHOME; $script:WingetText = ''
    Assert-True (-not (Get-WorkshopManagedPowerShell)) 'registry alone insufficient for provenance'

    # Capture, decode and parse the real detached worker without launching it.
    function Start-Process {
        [CmdletBinding()]param($FilePath, $ArgumentList, [switch]$NoNewWindow)
        $script:WorkerPath = $FilePath; $script:WorkerArgs = $ArgumentList
    }
    Start-WorkshopPowerShellUpdate 'C:\PowerShell\7\pwsh.exe' ([version]'7.5.1')
    $worker = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:WorkerArgs[-1]))
    Assert-True ($script:WorkerPath -like '*\WindowsPowerShell\v1.0\powershell.exe') 'worker independent from running pwsh'
    Assert-True ($worker -match "Wait-Process -Id $PID" -and $worker -match 'upgrade --id Microsoft.PowerShell' -and $worker -notmatch 'install-prerequisites') 'worker waits parent exit and never reenters installer'
    Assert-True ($worker -match 'version verification failed' -and $worker -match '3010') 'worker verifies installed version and reboot exit'
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($worker, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) 'encoded worker parses'

    $fixture = Join-Path $root ('.test-output\windows-update-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($fixture)
    try {
        foreach ($case in @('success', 'winget-fail', 'wrong-version', 'restart')) {
            $exitCode = switch ($case) { 'winget-fail' { 42 }; restart { 3010 }; default { 0 } }
            $actual = if ($case -eq 'wrong-version') { '7.5.0' } else { '7.5.1' }
            $preamble = @"
function Wait-Process { [CmdletBinding()]param(`$Id) }
function fixture-winget { `$global:LASTEXITCODE=$exitCode }
function fixture-pwsh { `$global:LASTEXITCODE=0; '$actual' }
"@
            $mocked = $worker.Replace("& 'C:\fixture-winget.exe'", 'fixture-winget').
                Replace("& 'C:\PowerShell\7\pwsh.exe'", 'fixture-pwsh')
            $file = Join-Path $fixture "$case.ps1"
            [IO.File]::WriteAllText($file, $preamble + "`n" + $mocked, [Text.UTF8Encoding]::new($true))
            foreach ($shell in @((Join-Path $PSHOME 'pwsh.exe'), $script:WorkerPath)) {
                $output = & $shell -NoProfile -NonInteractive -File $file 2>&1 | Out-String
                if ($case -eq 'success') {
                    Assert-True ($LASTEXITCODE -eq 0 -and $output.Contains('[PASS] PowerShell 7.5.1')) "mocked worker verifies successful update: $shell"
                }
                else {
                    $status = if ($case -eq 'restart') { '[WARN]' } else { '[FAIL]' }
                    Assert-True ($LASTEXITCODE -eq 1 -and $output.Contains($status) -and -not $output.Contains('[PASS]')) "mocked worker $case reports its status without success: $shell"
                }
                Assert-True (-not $output.Contains([string][char]27)) "redirected worker $case output stays plain: $shell"
            }
        }
    }
    finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
finally {
    $env:NVM_HOME=$savedHome; $env:NVM_SYMLINK=$savedLink; $env:PATH=$savedPath
}
Write-Host "PASS: $script:Passed Windows update assertions"
