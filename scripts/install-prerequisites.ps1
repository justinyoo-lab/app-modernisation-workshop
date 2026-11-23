[CmdletBinding()]
param(
    [string]$Track,
    [string]$ContainerEngine,
    [switch]$Update,
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.') -AllowInstall
if ($bootstrap.Handled) { exit $bootstrap.Code }

. (Join-Path $PSScriptRoot 'check-prerequisites.ps1') -Track $Track -ContainerEngine $ContainerEngine -Help:$Help

function Test-AzurePrompt {
    return (Test-WorkshopBootstrapInteractive) -and $Host.Name -eq 'ConsoleHost'
}

function Confirm-AzureAction {
    param([string]$Message)
    if (-not (Test-AzurePrompt)) { return $false }
    return (Read-Host "$Message [y/N]") -cmatch '^[yY]$'
}

function Invoke-AzureAction {
    param([string]$Name, [string[]]$Arguments)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Add-Check FAIL 'azure-action' "Could not find the $Name executable."; return $false }
    & $command.Source @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { Add-Check FAIL 'azure-action' "$Name failed (exit code $LASTEXITCODE). Check the error above."; return $false }
    return $true
}

function Initialize-AzureAccount {
    if (-not (Test-AzurePrompt)) { return }
    $account = Invoke-ToolProbe az @('account', 'show', '--query', 'state', '--output', 'tsv')
    if ($account.Code -ne 0 -or $account.Text -ne 'Enabled') {
        Add-Check WARN 'az-login' "Could not verify an enabled subscription (exit code $($account.Code)): $($account.Text). This may indicate missing authentication, insufficient permissions, or a network issue."
        if (Confirm-AzureAction 'Run az login with Azure CLI in this shell?') {
            if (-not (Invoke-AzureAction az @('login'))) { return }
        }
    }
    if (Confirm-AzureAction 'List subscriptions and manually select one for the workshop?') {
        $subscriptions = Invoke-ToolProbe az @('account', 'list', '--query', '[].[id,name]', '--output', 'tsv')
        if ($subscriptions.Code -ne 0 -or -not $subscriptions.Text) {
            Add-Check WARN 'azure-subscription' "Could not list subscriptions: $($subscriptions.Text)"
            return
        }
        Write-Host "Subscription ID / Name:`n$($subscriptions.Text)"
        $selected = Read-Host 'Subscription ID to switch to (Enter: keep current)'
        if (-not $selected) { return }
        $ids = @($subscriptions.Text -split '\r?\n' | ForEach-Object { ($_ -split "`t", 2)[0] })
        if ($selected -in $ids) { $null = Invoke-AzureAction az @('account', 'set', '--subscription', $selected) }
        else { Add-Check WARN 'azure-subscription' 'The subscription ID is not in the list. The subscription was not changed.' }
    }
}

function Initialize-ContainerappExtension {
    if (-not (Test-AzurePrompt)) { return }
    $extension = Invoke-ToolProbe az @('extension', 'show', '--name', 'containerapp', '--query', 'version', '--output', 'tsv')
    if ($extension.Code -ne 0 -or -not $extension.Text) {
        Add-Check WARN 'az-containerapp' "Could not query the extension (exit code $($extension.Code)): $($extension.Text)"
        if (Confirm-AzureAction 'Install or update the containerapp extension? This changes local Azure CLI extension files.') {
            $null = Invoke-AzureAction az @('extension', 'add', '--name', 'containerapp', '--upgrade')
        }
    }
}

function Initialize-AzdLogin {
    if (-not (Test-AzurePrompt)) { return }
    $login = Invoke-ToolProbe azd @('auth', 'login', '--check-status')
    if ($login.Code -ne 0) {
        Add-Check WARN 'azd-login' "Authentication check failed (exit code $($login.Code)): $($login.Text)"
        if (Confirm-AzureAction 'Run azd auth login in this shell? This is separate from Azure CLI authentication.') {
            $null = Invoke-AzureAction azd @('auth', 'login')
        }
    }
}

function Initialize-AzureProvider {
    param([string]$Provider)
    if (-not (Test-AzurePrompt)) { return }
    $state = Invoke-ToolProbe az @('provider', 'show', '--namespace', $Provider, '--query', 'registrationState', '--output', 'tsv')
    if ($state.Code -eq 0 -and $state.Text -eq 'Registered') { Add-Check PASS $Provider 'Registered'; return }
    Add-Check WARN $Provider "Registration state (exit code $($state.Code)): $($state.Text)"
    if ($state.Code -eq 0 -and $state.Text -in @('NotRegistered', 'Unregistered', 'Registering')) {
        if (Confirm-AzureAction "Register the $Provider provider in the current Azure CLI subscription and wait for completion? This changes subscription settings and requires registration permissions.") {
            $null = Invoke-AzureAction az @('provider', 'register', '--namespace', $Provider, '--wait')
            $state = Invoke-ToolProbe az @('provider', 'show', '--namespace', $Provider, '--query', 'registrationState', '--output', 'tsv')
        }
    }
    if ($state.Code -eq 0 -and $state.Text -eq 'Registered') { Add-Check PASS $Provider 'Registered' }
    else { Add-Check FAIL $Provider "Could not verify registration (exit code $($state.Code)): $($state.Text). Check the target subscription and registration permissions." }
}

function Initialize-AzureEnvironment {
    param([string]$SelectedTrack = 'dotnet')
    $script:CheckResults = [Collections.Generic.List[object]]::new()
    $script:CheckContext = 'Windows PowerShell'
    $previousDynamic = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
    try {
        $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
        if ((Invoke-ToolProbe az @('version', '--output', 'json')).Code -eq 0) {
            Initialize-AzureAccount
            Initialize-ContainerappExtension
            $account = Invoke-ToolProbe az @('account', 'show', '--query', 'state', '--output', 'tsv')
            if ($account.Code -eq 0 -and $account.Text -eq 'Enabled') {
                Show-AzureIdentity
                $providers = @('Microsoft.App', 'Microsoft.OperationalInsights', 'Microsoft.Storage', 'Microsoft.ContainerRegistry', 'Microsoft.ServiceBus')
                $providers += if ($SelectedTrack -eq 'java') { 'Microsoft.DBforPostgreSQL' } else { 'Microsoft.Sql' }
                foreach ($provider in $providers) {
                    Initialize-AzureProvider $provider
                }
            }
        }
        if ((Invoke-ToolProbe azd @('version')).Code -eq 0) { Initialize-AzdLogin }
    }
    finally { $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = $previousDynamic }
    return @($script:CheckResults | Where-Object Status -eq 'FAIL').Count -eq 0
}

function Confirm-ToolInstall {
    param([string]$Description)
    if (-not (Test-WorkshopBootstrapInteractive)) { return $false }
    Write-Host $Description
    $answer = Read-Host 'Run this action? [y/N]'
    return $answer -ceq 'y' -or $answer -ceq 'Y'
}

function Update-ProcessPath {
    $existing = @($env:PATH -split ';' | Where-Object { $_ })
    foreach ($scope in @('Machine', 'User')) {
        $paths = [Environment]::GetEnvironmentVariable('Path', $scope) -split ';'
        foreach ($path in $paths) {
            $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
            if ($expanded -and $expanded -notin $existing) { $existing += $expanded }
        }
    }
    $env:PATH = $existing -join ';'
    foreach ($name in @('NVM_HOME', 'NVM_SYMLINK')) {
        if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
            foreach ($scope in @('User', 'Machine')) {
                $value = [Environment]::GetEnvironmentVariable($name, $scope)
                if ($value) {
                    [Environment]::SetEnvironmentVariable($name, [Environment]::ExpandEnvironmentVariables($value), 'Process')
                    break
                }
            }
        }
    }
}

. (Join-Path $PSScriptRoot 'windows-prerequisite-updates.ps1')

function Install-WorkshopDotnetSdk {
    param([switch]$Update)
    if (-not (Test-WorkshopBootstrapInteractive)) { return $false }
    $sdks = Invoke-ToolProbe dotnet @('--list-sdks')
    $installed = @()
    if ($sdks.Code -eq 0) {
        $installed = @([regex]::Matches($sdks.Text, '(?m)^(10\.\d+\.\d+)\s+\[') |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
    }
    if ($installed.Count -and -not $Update) {
        Write-WorkshopMessage '[INFO] A stable .NET 10 SDK is installed. No update will run without -Update.'
        return $true
    }
    if (-not $installed.Count) {
        Write-WorkshopMessage "[INFO] Could not verify a stable .NET 10 SDK (exit code $($sdks.Code)): $($sdks.Text)"
    }
    if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-WorkshopMessage '[WARN] Automatic .NET 10 SDK installation requires winget. Official installation guide: https://dotnet.microsoft.com/download/dotnet/10.0'
        return $true
    }
    $arguments = @('install', '--id', 'Microsoft.DotNet.SDK.10', '--exact', '--source', 'winget')
    $target = $null
    if ($Update) {
        $show = Invoke-ToolProbe winget @('show', '--id', 'Microsoft.DotNet.SDK.10', '--exact', '--source', 'winget', '--versions', '--disable-interactivity')
        $versions = @([regex]::Matches($show.Text, '(?m)^\s*(10\.\d+\.\d+)\s*$') |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
        if ($show.Code -ne 0 -or -not $versions.Count) {
            Write-WorkshopMessage "[FAIL] Could not query the latest stable .NET 10 SDK version from winget (exit code $($show.Code)): $($show.Text)"
            return $false
        }
        $target = $versions[0]
        if ($installed.Count -and $installed[0] -ge $target) {
            Write-WorkshopMessage "[PASS] Keeping .NET SDK $($installed[0]) (no downgrade)."
            return $true
        }
        $arguments += @('--version', "$target")
    }
    if (-not (Confirm-ToolInstall ".NET 10 SDK $target`: install or update winget package Microsoft.DotNet.SDK.10 on the Windows host. Other SDK major versions and global.json will not change. The installer may replace older patches in the same feature band. Network access and administrator approval may be required. Review the terms shown by winget.")) {
        Write-WorkshopMessage '[INFO] Skipping .NET 10 SDK installation or update.'
        return $true
    }
    & winget @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-WorkshopMessage "[FAIL] .NET 10 SDK installation failed (exit code $LASTEXITCODE)."
        return $false
    }
    Update-ProcessPath
    $sdks = Invoke-ToolProbe dotnet @('--list-sdks')
    if ($sdks.Code -ne 0 -or $sdks.Text -notmatch '(?m)^10\.\d+\.\d+\s+\[') {
        Write-WorkshopMessage "[FAIL] Could not verify a stable .NET 10 SDK after installation (exit code $($sdks.Code)): $($sdks.Text). Check PATH and the installation."
        return $false
    }
    if ($target -and "$($sdks.Text)`n" -notmatch "(?m)^$([regex]::Escape($target.ToString()))\s+\[") {
        Write-WorkshopMessage "[FAIL] Could not verify installation of the requested .NET SDK $target`: $($sdks.Text)"
        return $false
    }
    Write-WorkshopMessage '[PASS] Verified a stable .NET 10 SDK installation.'
    return $true
}

function Install-WorkshopJava {
    param([int]$Major, [switch]$Update)
    if (-not (Test-WorkshopBootstrapInteractive)) { return $false }
    if ($Major -notin @(8, 25)) { Write-WorkshopMessage '[FAIL] Supported JDK versions are 8 and 25.'; return $false }
    $existing = Find-WorkshopJava -Major $Major
    if ($existing -and -not $Update) {
        Write-WorkshopMessage "[INFO] Keeping Temurin JDK $Major`: $($existing.Home)"
        return $true
    }
    if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-WorkshopMessage '[WARN] Automatic Temurin installation requires winget. Install manually from https://adoptium.net/temurin/releases/'
        return $true
    }
    $package = "EclipseAdoptium.Temurin.$Major.JDK"
    if ($existing -and $Update) {
        $list = Invoke-ToolProbe winget @('list', '--id', $package, '--exact', '--source', 'winget', '--disable-interactivity')
        $show = Invoke-ToolProbe winget @('show', '--id', $package, '--exact', '--source', 'winget', '--versions', '--disable-interactivity')
        $versions = @([regex]::Matches($show.Text, "(?m)^\s*($Major\.\d+\.\d+(?:\.\d+)?)\s*$") |
            ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
        if ($list.Code -eq 0 -and $show.Code -eq 0 -and $versions.Count -and
            $list.Text -match "$([regex]::Escape($package))\s+($Major\.\d+\.\d+(?:\.\d+)?)(?:\s|$)") {
            $installed = [version]$Matches[1]
            if ($installed -ge $versions[0]) {
                Write-WorkshopMessage "[INFO] Keeping Temurin JDK $Major package $installed (already current; no downgrade)."
                return $true
            }
        }
        else {
            Write-WorkshopMessage "[WARN] Could not verify the installed/latest Temurin JDK $Major package versions. Update approval is still required."
        }
    }
    if (-not (Confirm-ToolInstall "Temurin JDK $Major`: install or update winget package $package. Administrator approval is required. ADDLOCAL=FeatureMain leaves system PATH, JAVA_HOME, and file associations unchanged.")) {
        Write-WorkshopMessage "[INFO] Skipping Temurin JDK $Major installation or update."
        return $true
    }
    $verb = if ($existing) { 'upgrade' } else { 'install' }
    & winget $verb --id $package --exact --source winget --custom 'ADDLOCAL=FeatureMain' | Out-Host
    $code = $LASTEXITCODE
    # WinGet reports this status when an installed package is already current.
    if ($code -ne 0 -and -not ($existing -and $code -eq -1978335189)) {
        Write-WorkshopMessage "[FAIL] Temurin JDK $Major installation failed (exit code $code)."
        return $false
    }
    if (-not (Find-WorkshopJava -Major $Major)) {
        Write-WorkshopMessage "[FAIL] Could not verify java and javac for Temurin JDK $Major after installation."
        return $false
    }
    Write-WorkshopMessage "[PASS] Verified the Temurin JDK $Major installation."
    return $true
}

function Install-WindowsTools {
    param([string]$SelectedTrack)
    if (-not (Test-WorkshopBootstrapInteractive)) { return $false }
    $nodeInstalled = Install-WorkshopNode -Update:$Update
    $tools =
        @(
            @{ Command='az'; Package='Microsoft.AzureCLI'; Name='Azure CLI' },
            @{ Command='azd'; Package='Microsoft.Azd'; Name='Azure Developer CLI' },
            @{ Command='gh'; Package='GitHub.cli'; Name='GitHub CLI' },
            @{ Command='modernize'; Package='GitHub.Copilot.modernization.agent'; Name='Modernize CLI' }
        )
    $sdkInstalled = $true
    if ($SelectedTrack -eq 'java') {
        foreach ($major in @(8, 25)) {
            if (-not (Install-WorkshopJava -Major $major -Update:$Update)) { $sdkInstalled = $false }
        }
    }
    else { $sdkInstalled = Install-WorkshopDotnetSdk -Update:$Update }
    $failed = -not $nodeInstalled -or -not $sdkInstalled
    foreach ($tool in $tools) {
        $existing = Get-Command $tool.Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existing) {
            Write-WorkshopMessage "[INFO] $($tool.Name): found in PATH ($($existing.Source)). No installation or update will run."
            continue
        }
        if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
            Write-WorkshopMessage "[WARN] Automatic $($tool.Name) installation requires Windows Package Manager (winget)."
            continue
        }
        if (Confirm-ToolInstall "$($tool.Name): install winget package $($tool.Package) on the Windows host. Network access and administrator approval may be required. Review the terms shown by winget.") {
            & winget install --id $tool.Package --exact --source winget | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-WorkshopMessage "[FAIL] $($tool.Name) installation failed (exit code $LASTEXITCODE)."
                $failed = $true
            }
            else { Update-ProcessPath }
        }
    }
    return (-not $failed)
}

function Invoke-InstallPrerequisiteMain {
    if ($Help) {
        Write-Host './scripts/install-prerequisites.ps1 -Track java|dotnet [-ContainerEngine docker|podman] [-Update]'
        return 0
    }
    if ($Track -cnotin @('java', 'dotnet')) { Write-WorkshopMessage '[FAIL] Specify -Track java or -Track dotnet.'; return 2 }
    if (-not $IsWindows) { Write-WorkshopMessage '[FAIL] This installer is Windows-only. For the Java track, run ./scripts/install-prerequisites.sh.'; return 1 }
    try { $engine = Resolve-ContainerEngine $ContainerEngine }
    catch [ArgumentException] { Write-WorkshopMessage "[FAIL] $($_.Exception.Message)"; return 2 }
    if (-not (Test-WorkshopBootstrapInteractive)) {
        Write-WorkshopMessage '[FAIL] Installation requires an interactive terminal. Nothing will be installed in a noninteractive session.'
        return 1
    }
    $hostResult = 0
    if ($Update) {
        $hostResult = Update-WorkshopWindowsHost
        if ($hostResult -eq 3010) { return 1 }
    }
    Write-Host 'Installation target: Windows host. Existing tools will not be updated without -Update.'
    $installed = Install-WindowsTools $Track
    if ($hostResult -ne 0) { $installed = $false }
    if (-not $installed) {
        Write-WorkshopMessage '[FAIL] Installation or update did not complete. Resolve the issues above and rerun. Further tool execution will be skipped.'
        return 1
    }
    $prepared = Initialize-AzureEnvironment -SelectedTrack $Track
    Write-WorkshopMessage '[INFO] Running read-only prerequisite checks from ./scripts/check-prerequisites.ps1. Verify MANUAL items yourself.'
    $result = Invoke-PrerequisiteMain
    if (-not $installed -or -not $prepared -or $result -ne 0) { return 1 }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-InstallPrerequisiteMain) }
