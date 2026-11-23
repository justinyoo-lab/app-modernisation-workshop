[CmdletBinding()]
param(
    [ValidateSet('dotnet')]
    [string]$Track = 'dotnet',
    [switch]$Help,
    [switch]$Yes
)

function Get-VmHelperDirectory {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')) { return $PSScriptRoot }
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts'))
}

function Assert-VmInstallerContext {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) {
        throw 'Run this installer from Windows x64 PowerShell.'
    }
    if (-not (Test-WorkshopBootstrapInteractive)) { throw 'Installation is skipped in CI or non-interactive environments.' }
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $account = Get-LocalUser -Name appmoduser -ErrorAction Stop
    if ($current.IsSystem -or $current.User.Value -ne $account.SID.Value) {
        throw 'Sign in as appmoduser and run this from an elevated terminal of the same account.'
    }
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Reopen the appmoduser terminal as administrator.'
    }
}

function Confirm-VmAction {
    param([string]$Message)
    if (-not (Test-WorkshopBootstrapInteractive)) { return $false }
    if ($Yes) {
        Write-WorkshopMessage "[INFO] Approved by -Yes: $Message"
        return $true
    }
    Write-Host $Message
    return (Read-Host 'Continue? [y/N]') -cmatch '^[yY]$'
}

function Test-VmRebootPending {
    return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

function Invoke-VmInstaller {
    param([string]$Command, [string[]]$Arguments)
    $executable = Get-Command $Command -CommandType Application -ErrorAction Stop | Select-Object -First 1
    & $executable.Source @Arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -in @(1641, 3010)) {
        $script:VmRestartRequired = $true
        Write-WorkshopMessage '[MANUAL] The installer requested a restart. Restart manually and rerun this script.'
        return $true
    }
    if ($code -ne 0) { throw "$Command installation failed (exit code $code)." }
    return $true
}

function Get-VmWingetVersion {
    param([string]$Id, [string]$VersionPattern)
    $arguments = @('show', '--id', $Id, '--exact', '--source', 'winget', '--versions', '--disable-interactivity')
    if ($Yes) { $arguments += '--accept-source-agreements' }
    $text = (& winget @arguments 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query $Id versions. Check the source agreements and network access in winget: $text"
    }
    $versions = @($text -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match $VersionPattern } | ForEach-Object { [version]$_ } | Sort-Object -Descending)
    if (-not $versions.Count) { throw "No stable $Id version matches the required pattern: $VersionPattern" }
    return $versions[0].ToString()
}

function Install-VmPackage {
    param(
        [string]$Id,
        [string]$Name,
        [scriptblock]$TestInstalled,
        [string]$VersionPattern,
        [string[]]$ExtraArguments = @()
    )
    if (& $TestInstalled) { Write-WorkshopMessage "[PASS] $Name is installed. Keeping the existing installation."; return $true }
    if (-not (Confirm-VmAction "Install $Name ($Id). Review the license and installation details shown.")) {
        Write-WorkshopMessage "[MANUAL] Skipped the $Name installation."
        return $false
    }
    $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget')
    if ($Yes) { $arguments += @('--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') }
    if ($VersionPattern) { $arguments += @('--version', (Get-VmWingetVersion $Id $VersionPattern)) }
    $arguments += $ExtraArguments
    $null = Invoke-VmInstaller winget $arguments
    if ($script:VmRestartRequired) { return $false }
    if (Get-Command Update-ProcessPath -CommandType Function -ErrorAction SilentlyContinue) { Update-ProcessPath }
    if (-not (& $TestInstalled)) { throw "Could not verify $Name after installation. Rerun from a new terminal." }
    Write-WorkshopMessage "[PASS] Verified the $Name installation."
    return $true
}

function Initialize-VmWinget {
    if (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue) { return $true }
    if (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop) {
        if (-not (Confirm-VmAction 'Register App Installer (Windows Package Manager) for the current user.')) { return $false }
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
    }
    else {
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
            if (-not (Confirm-VmAction 'Install the NuGet package provider required to prepare WinGet.')) { return $false }
            $null = Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -ErrorAction Stop
        }
        if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
            if (-not (Confirm-VmAction 'Install the Microsoft.WinGet.Client module from PSGallery for the current user.')) { return $false }
            Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force -ErrorAction Stop
        }
        if (-not (Confirm-VmAction 'Install or repair the stable WinGet package manager for all users with Microsoft.WinGet.Client.')) { return $false }
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Host
    }
    if (-not (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'winget was not found. Rerun from a new elevated terminal.'
    }
    return $true
}

function Test-VmPowerShell7 {
    $path = Find-WorkshopPowerShell
    if (-not $path) { return $false }
    $major = & $path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major'
    if ($LASTEXITCODE -ne 0 -or "$major".Trim() -ne '7') { throw 'Check the stable PowerShell 7.x path.' }
    return $true
}

function Install-VmPowerShell {
    return (Install-VmPackage Microsoft.PowerShell 'PowerShell 7.x' `
        -VersionPattern '^7\.\d+\.\d+(?:\.\d+)?$' -TestInstalled { Test-VmPowerShell7 })
}

function Get-VmWslExecutable {
    $command = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $path = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
}

function Invoke-VmWindowsFeature {
    param(
        [ValidateSet('VirtualMachinePlatform', 'MSMQ-Server')]
        [string]$FeatureName,
        [switch]$Enable
    )
    # DISM cmdlets can fail with "Class not registered" in MSIX PowerShell 7.
    $command = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    if (__ENABLE__) {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName '__FEATURE__' -All -NoRestart -ErrorAction Stop
        [pscustomobject]@{ RestartNeeded = [bool]$result.RestartNeeded } | ConvertTo-Json -Compress
    }
    else {
        $result = Get-WindowsOptionalFeature -Online -FeatureName '__FEATURE__' -ErrorAction Stop
        [pscustomobject]@{ State = [string]$result.State } | ConvertTo-Json -Compress
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@
    $enabled = if ($Enable) { '$true' } else { '$false' }
    $command = $command.Replace('__ENABLE__', $enabled).Replace('__FEATURE__', $FeatureName)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $probe = Invoke-ToolProbe $engine @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
    if ($probe.Code -ne 0) {
        throw "Windows PowerShell feature operation failed for $FeatureName (exit code $($probe.Code)): $($probe.Text)"
    }
    $result = $probe.Text | ConvertFrom-Json -ErrorAction Stop
    if (($Enable -and $result.RestartNeeded -isnot [bool]) -or
        (-not $Enable -and [string]::IsNullOrWhiteSpace($result.State))) {
        throw "Invalid Windows PowerShell feature response for ${FeatureName}: $($probe.Text)"
    }
    return $result
}

function Test-VmWslPlatform {
    $wsl = Get-VmWslExecutable
    if (-not $wsl) { return $false }
    $feature = Invoke-VmWindowsFeature -FeatureName VirtualMachinePlatform
    if ("$($feature.State)" -ne 'Enabled') { return $false }
    return (Invoke-ToolProbe $wsl @('--status')).Code -eq 0
}

function Install-VmWslPlatform {
    if (Test-VmWslPlatform) { Write-WorkshopMessage '[PASS] WSL2 platform is ready.'; return $true }
    $feature = Invoke-VmWindowsFeature -FeatureName VirtualMachinePlatform
    if ("$($feature.State)" -in @('EnablePending', 'DisablePending')) { $script:VmRestartRequired = $true; return $false }
    $wsl = Get-VmWslExecutable
    if (-not $wsl) { throw 'wsl.exe was not found. Check the Windows 11 image and the WSL documentation.' }
    if (-not (Confirm-VmAction 'Install the WSL2 platform without a Linux distribution (wsl.exe --install --no-distribution). A manual restart is required. Ubuntu is installed in a later step after the restart.')) {
        return $false
    }
    $null = Invoke-VmInstaller $wsl @('--install', '--no-distribution')
    if ($script:VmRestartRequired) { return $false }
    if (Test-VmWslPlatform) { Write-WorkshopMessage '[PASS] WSL2 platform is ready.'; return $true }
    # wsl.exe can return 0 while VirtualMachinePlatform waits for a restart.
    $script:VmRestartRequired = $true
    Write-WorkshopMessage '[MANUAL] The WSL2 platform becomes available after a restart. Restart manually and rerun.'
    return $false
}

function Get-VmUbuntuVersion {
    $list = Invoke-ToolProbe wsl.exe @('--list', '--verbose')
    $text = $list.Text -replace "`0", ''
    if ($list.Code -ne 0) {
        # WSL reports an empty distribution list as a nonzero exit code.
        if ($text -match '^\s*Windows Subsystem for Linux has no installed distributions\.(?:\s|$)') { return 0 }
        throw "Failed to list WSL distributions: $text"
    }
    if ($text -match '(?m)^\s*\*?\s*Ubuntu\s+\S+\s+([12])\s*$') {
        return [int]$Matches[1]
    }
    return 0
}

function Install-VmUbuntu {
    if (-not (Test-VmWslPlatform)) {
        Write-WorkshopMessage '[MANUAL] Ubuntu requires the WSL2 platform. Complete the WSL2 platform step and restart first.'
        return $false
    }
    $version = Get-VmUbuntuVersion
    if ($version -eq 1) { throw 'The existing Ubuntu uses WSL1. Preserve its data and convert it to WSL2 manually.' }
    if ($version -eq 2) { Write-WorkshopMessage '[PASS] Verified Ubuntu on WSL2 for appmoduser.'; return $true }
    if (-not (Confirm-VmAction 'Install Ubuntu on WSL2 for appmoduser. Set up the first Linux user manually afterward.')) {
        return $false
    }
    $null = Invoke-VmInstaller wsl.exe @('--install', '--distribution', 'Ubuntu', '--no-launch')
    if ($script:VmRestartRequired) { return $false }
    if ((Get-VmUbuntuVersion) -ne 2) { throw 'Could not verify Ubuntu on WSL2. Check for a pending restart and the WSL status.' }
    Write-WorkshopMessage '[MANUAL] Run wsl -d Ubuntu to set up the first Linux user.'
    return $true
}

function Install-VmMsmq {
    $feature = Invoke-VmWindowsFeature -FeatureName MSMQ-Server
    if ("$($feature.State)" -in @('EnablePending', 'DisablePending')) {
        $script:VmRestartRequired = $true
        return $false
    }
    if ("$($feature.State)" -ne 'Enabled') {
        if (-not (Confirm-VmAction 'Enable MSMQ Server and the required Windows features. No automatic restart.')) { return $false }
        $result = Invoke-VmWindowsFeature -FeatureName MSMQ-Server -Enable
        if ($result.RestartNeeded) { $script:VmRestartRequired = $true; return $false }
        if ((Invoke-VmWindowsFeature -FeatureName MSMQ-Server).State -ne 'Enabled') {
            throw 'Could not verify that the MSMQ feature is enabled.'
        }
    }
    $service = Get-Service MSMQ -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        if (-not (Confirm-VmAction 'Set the MSMQ service to start automatically and start it. No queues or data are created.')) { return $false }
        Set-Service MSMQ -StartupType Automatic -ErrorAction Stop
        Start-Service MSMQ -ErrorAction Stop
        $service = Get-Service MSMQ -ErrorAction Stop
        $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    }
    Write-WorkshopMessage '[PASS] Verified MSMQ Server and its running service.'
    return $true
}

function Test-VmFrameworkRuntime {
    $path = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    if (-not (Test-Path $path)) { return $false }
    return (Get-ItemProperty $path -Name Release -ErrorAction Stop).Release -ge 528040
}

function Install-VmDotnetSdk {
    param([ValidateSet(10, 11)][int]$Major)
    return (Install-VmPackage -Id "Microsoft.DotNet.SDK.$Major" -Name ".NET $Major SDK" `
        -VersionPattern "^$Major\.\d+\.\d+$" -TestInstalled {
            $probe = Invoke-ToolProbe dotnet @('--list-sdks')
            $probe.Code -eq 0 -and $probe.Text -match "(?m)^$Major\.\d+\.\d+\s+\["
        })
}

function Test-VmVisualCppRuntime {
    foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32\$name") -PathType Leaf)) { return $false }
    }
    return $true
}

function Install-VmVisualCppRuntime {
    return (Install-VmPackage -Id Microsoft.VCRedist.2015+.x64 -Name 'Microsoft Visual C++ v14 Redistributable (x64)' `
        -TestInstalled { Test-VmVisualCppRuntime })
}

function Get-VmPostgresClient {
    $paths = @((Join-Path $env:ProgramFiles 'PostgreSQL\18\bin\psql.exe'))
    $command = Get-Command psql -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $paths += $command.Source }
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $probe = Invoke-ToolProbe $path @('--version')
        if ($probe.Code -eq 0 -and $probe.Text -match '^psql \(PostgreSQL\) 18\.\d+(?:\s|$)') { return $path }
        Write-WorkshopMessage "[WARN] Could not verify PostgreSQL 18 at '$path' (exit code $($probe.Code)). Output: $($probe.Text)"
    }
    Write-WorkshopMessage "[INFO] No working PostgreSQL 18 client was found. Checked: $($paths -join ', ')"
}

function Test-VmPostgresClient {
    return [bool](Get-VmPostgresClient)
}

function Set-VmPostgresPath {
    $client = Get-VmPostgresClient
    if (-not $client) { throw 'Cannot configure PATH without a working PostgreSQL 18 client.' }
    $directory = Split-Path -Parent $client
    $environment = Get-Item -LiteralPath 'HKCU:\Environment' -ErrorAction Stop
    $userPath = [string]$environment.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $entries = @($userPath -split ';' | ForEach-Object {
        [Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"')).TrimEnd('\', '/')
    })
    if ($directory.TrimEnd('\', '/') -notin $entries) {
        if (-not (Confirm-VmAction "Append '$directory' to appmoduser's user PATH. Existing entries and their order will be preserved.")) {
            Write-WorkshopMessage '[MANUAL] PostgreSQL 18 user PATH configuration was skipped.'
            return $false
        }
        $separator = if ($userPath -and -not $userPath.EndsWith(';')) { ';' } else { '' }
        $kind = if ($environment.GetValueNames() -contains 'Path') {
            $environment.GetValueKind('Path')
        } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
        Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value "$userPath$separator$directory" `
            -Type $kind -ErrorAction Stop
    }
    Update-ProcessPath
    if (-not (Test-VmCommand psql)) { throw 'User PATH was configured, but psql could not run in the installer process.' }
    $command = Get-Command psql -CommandType Application -ErrorAction Stop | Select-Object -First 1
    if ($command.Source -ine $client) {
        Write-WorkshopMessage "[WARN] Another psql takes precedence in PATH: '$($command.Source)'. Existing order was preserved. Use '$client' explicitly for PostgreSQL 18."
    }
    Write-WorkshopMessage '[PASS] PostgreSQL 18 directory is in the user PATH and the installer PATH. Restart Windows Terminal to refresh its environment; the calling shell is unchanged.'
    return $true
}

function Install-VmPostgresClient {
    if (-not (Install-VmVisualCppRuntime)) {
        Write-WorkshopMessage '[MANUAL] PostgreSQL 18 client requires the x64 Visual C++ runtime. Complete that installation and any requested restart first.'
        return $false
    }
    if (-not (Install-VmPackage -Id PostgreSQL.PostgreSQL.18 -Name 'PostgreSQL 18 command-line tools (client only)' `
        -ExtraArguments @('--override', '--mode unattended --unattendedmodeui minimal --enable-components commandlinetools --disable-components server,pgAdmin,stackbuilder') `
        -TestInstalled { Test-VmPostgresClient })) { return $false }
    return (Set-VmPostgresPath)
}

function Install-VmNvm {
    $nvm = Get-Command nvm -CommandType Application -ErrorAction SilentlyContinue
    if ($nvm) {
        $version = Get-WorkshopReleaseVersion (Invoke-ToolProbe nvm @('version'))
        if (-not $version -or $version.Major -ne 2) { throw 'The existing nvm is not replaced automatically. Prepare nvm-windows 2.x manually.' }
    }
    else {
        $nodeLink = Join-Path $env:ProgramFiles 'nodejs'
        if ((Get-Command node -CommandType Application -ErrorAction SilentlyContinue) -or
            $env:NVM_HOME -or $env:NVM_SYMLINK -or (Test-Path -LiteralPath $nodeLink)) {
            throw 'Preserving the existing Node.js or NVM paths. Migrate to nvm-windows 2.x manually.'
        }
        $installed = Install-VmPackage -Id AuthorSoftware.NVMWindows -Name 'nvm-windows 2.x' -VersionPattern '^2\.\d+\.\d+$' -TestInstalled {
            $v = Get-WorkshopReleaseVersion (Invoke-ToolProbe nvm @('version'))
            $v -and $v.Major -eq 2
        }
        if (-not $installed) { return $false }
    }
    $probe = Invoke-ToolProbe nvm @('config', 'get', 'auto_install', '--json')
    if ($probe.Code -ne 0) { throw 'Could not read the nvm auto_install setting.' }
    $config = $probe.Text | ConvertFrom-Json -ErrorAction Stop
    if ($config.auto_install -isnot [bool]) { throw 'The nvm auto_install setting is invalid.' }
    if ($config.auto_install) {
        if (-not (Confirm-VmAction 'Set nvm auto_install to false to prevent Node.js installations without consent.')) { return $false }
        $change = Invoke-ToolProbe nvm @('config', 'set', 'auto_install=false')
        if ($change.Code -ne 0) { throw "Failed to disable nvm auto_install: $($change.Text)" }
    }
    if (-not (Get-WorkshopNvmConfiguration)) {
        throw 'Set auto_install to false in the nvm config, check root, mode and enabled, and rerun.'
    }
    if ($Yes) {
        # Limit the shared Node installer's consent override to this VM call.
        return (& {
            function Confirm-ToolInstall {
                param([string]$Message)
                return (Confirm-VmAction $Message)
            }
            Install-WorkshopNode
        })
    }
    return Install-WorkshopNode
}

function Get-VmVsInstance {
    param([string]$Product, [string[]]$Requires = @())
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return }
    $arguments = @('-products', "Microsoft.VisualStudio.Product.$Product", '-version', '[18.0,19.0)', '-latest', '-format', 'json', '-utf8')
    if ($Requires.Count) { $arguments += '-requires'; $arguments += $Requires }
    $probe = Invoke-ToolProbe $vswhere $arguments
    if ($probe.Code -ne 0) { throw "Failed to query Visual Studio: $($probe.Text)" }
    $instances = @($probe.Text | ConvertFrom-Json -ErrorAction Stop)
    if ($instances.Count) { return $instances[0] }
}

function Install-VmVisualStudio {
    param([ValidateSet('BuildTools')][string]$Product, [string]$ConfigFile)
    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json -ErrorAction Stop
    $components = @($config.components)
    if (Get-VmVsInstance $Product $components) { Write-WorkshopMessage "[PASS] Verified the Visual Studio 2026 $Product configuration."; return $true }
    $instance = Get-VmVsInstance $Product
    if ($instance) {
        if (-not (Confirm-VmAction "Add the missing components from $ConfigFile to the existing Visual Studio 2026 $Product. Close Visual Studio first.")) { return $false }
        $setup = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
        # setup.exe does not support the bootstrapper's --wait switch.
        $arguments = "modify --installPath `"$($instance.installationPath)`" --config `"$ConfigFile`" --passive --norestart"
        $process = Start-Process -FilePath $setup -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -in @(1641, 3010)) { $script:VmRestartRequired = $true; return $false }
        if ($process.ExitCode -ne 0) { throw "Visual Studio modification failed (exit code $($process.ExitCode))." }
        if (-not (Get-VmVsInstance $Product $components)) { throw 'Could not verify the requested Visual Studio components.' }
        return $true
    }
    $override = "--passive --wait --norestart --config `"$ConfigFile`""
    return Install-VmPackage -Id "Microsoft.VisualStudio.$Product" -Name "Visual Studio 2026 $Product" `
        -VersionPattern '^18\.\d+\.\d+$' -ExtraArguments @('--override', $override) `
        -TestInstalled { [bool](Get-VmVsInstance $Product $components) }
}

function Get-VmCopilotVersion {
    foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in Get-ChildItem $root -ErrorAction Stop) {
            $app = Get-ItemProperty $key.PSPath -ErrorAction Stop
            if ($app.DisplayName -match '^GitHub Copilot( App)?$') {
                $version = $null
                if (-not [version]::TryParse($app.DisplayVersion, [ref]$version)) { throw 'Could not read the installed Copilot app version.' }
                return $version
            }
        }
    }
}

function Install-VmCopilot {
    $existing = Get-VmCopilotVersion
    if ($existing) { Write-WorkshopMessage "[PASS] Keeping GitHub Copilot app $existing. Sign in manually."; return $true }
    if (-not (Confirm-VmAction 'Install the GitHub Copilot app from the official github/app stable release. This is not Copilot CLI.')) { return $false }
    $release = Invoke-RestMethod 'https://api.github.com/repos/github/app/releases/latest' -ErrorAction Stop
    if ($release.prerelease -or $release.draft -or $release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$') {
        throw 'Could not find a stable Copilot app release.'
    }
    $expectedVersion = [version]$Matches[1]
    $assets = @($release.assets | Where-Object name -eq 'GitHub-Copilot-windows-x64.msi')
    if ($assets.Count -ne 1 -or $assets[0].browser_download_url -notlike 'https://github.com/github/app/releases/download/*') {
        throw 'Could not find the official Windows x64 MSI.'
    }
    $path = Join-Path $env:TEMP ("appmod-copilot-$([guid]::NewGuid().ToString('N')).msi")
    try {
        Invoke-WebRequest -Uri $assets[0].browser_download_url -OutFile $path -UseBasicParsing -ErrorAction Stop
        if ($assets[0].digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $Matches[1]) { throw 'The Copilot MSI hash does not match.' }
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or
            $signature.SignerCertificate.Subject -notmatch '(CN|O)="?GitHub(,? Inc\.?)?"?(,|$)') {
            throw 'Could not verify a valid GitHub signature on the Copilot MSI.'
        }
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') `
            -ArgumentList "/i `"$path`" /passive /norestart" -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -in @(1641, 3010)) { $script:VmRestartRequired = $true; return $false }
        if ($process.ExitCode -ne 0) { throw "Copilot app MSI installation failed (exit code $($process.ExitCode))." }
        $installed = Get-VmCopilotVersion
        if (-not $installed -or $installed -lt $expectedVersion) { throw 'Could not verify the Copilot app version after installation.' }
        Write-WorkshopMessage "[PASS] Installed GitHub Copilot app $installed. Sign in manually."
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    }
}

function Test-VmCommand {
    param([string]$Name, [string[]]$Arguments = @('--version'))
    $probe = Invoke-ToolProbe $Name $Arguments
    return $probe.Code -eq 0 -and -not [string]::IsNullOrWhiteSpace($probe.Text)
}

function Test-VmDesktopApp {
    param([string[]]$Paths)
    return @($Paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0
}

function Install-VmMicrosoftMsi {
    param([string]$Name, [string]$Uri, [string]$Sha256, [scriptblock]$TestInstalled, [string]$Properties = '')
    if (& $TestInstalled) { Write-WorkshopMessage "[PASS] $Name is installed. Keeping the existing installation."; return $true }
    if (-not (Confirm-VmAction "Install $Name from the official Microsoft MSI and accept its license terms. Review https://www.microsoft.com/licensing/terms/ before continuing. No database or instance will be created.")) {
        return $false
    }
    $path = Join-Path $env:TEMP ("appmod-microsoft-$([guid]::NewGuid().ToString('N')).msi")
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $path -UseBasicParsing -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $Sha256) { throw "The $Name MSI hash does not match." }
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
            throw "Could not verify a valid Microsoft signature on the $Name MSI."
        }
        $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') `
            -ArgumentList "/i `"$path`" /passive /norestart $Properties" -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -in @(1641, 3010)) { $script:VmRestartRequired=$true; return $false }
        if ($process.ExitCode -ne 0) { throw "$Name MSI installation failed (exit code $($process.ExitCode))." }
        Update-ProcessPath
        if (-not (& $TestInstalled)) { throw "Could not verify $Name after installation." }
        Write-WorkshopMessage "[PASS] Verified the $Name installation."
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    }
}

function Test-VmIisExpress {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ((Test-Path -LiteralPath (Join-Path $base 'IIS Express\iisexpress.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $base 'IIS Express\AppServer\applicationhost.config') -PathType Leaf)) { return $true }
    }
    return $false
}

function Install-VmIisExpress {
    return (Install-VmMicrosoftMsi -Name 'IIS Express 10 x64' `
        -Uri 'https://download.visualstudio.microsoft.com/download/pr/4c26ccd0-4528-45dc-aa5c-72c557a58703/341a554d60163f8b275d1d6f97149d03a18f59bb340a15f1bd70659f237537fe/iisexpress_amd64_en-us.msi' `
        -Sha256 '341a554d60163f8b275d1d6f97149d03a18f59bb340a15f1bd70659f237537fe' -TestInstalled { Test-VmIisExpress })
}

function Test-VmLocalDb {
    $localDb = Get-Command SqlLocalDB.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($localDb) { $candidates += $localDb.Source }
    foreach ($version in @('170', '160', '150')) {
        $candidates += Join-Path $env:ProgramFiles "Microsoft SQL Server\$version\Tools\Binn\SqlLocalDB.exe"
    }
    $found = $false
    foreach ($path in $candidates) {
        if ((Test-Path -LiteralPath $path) -and (Test-VmCommand $path @('versions'))) { $found = $true; break }
    }
    return $found
}

function Install-VmLocalDb {
    return (Install-VmMicrosoftMsi -Name 'SQL Server 2025 Express LocalDB x64' `
        -Uri 'https://download.visualstudio.microsoft.com/download/pr/4c26ccd0-4528-45dc-aa5c-72c557a58703/0891bf47652d88f06d76a339a5db37ddc9c801d1e973e14b3b551609f1cfa4cb/SqlLocalDB.msi' `
        -Sha256 '0891bf47652d88f06d76a339a5db37ddc9c801d1e973e14b3b551609f1cfa4cb' `
        -Properties 'IACCEPTSQLLOCALDBLICENSETERMS=YES' -TestInstalled { Test-VmLocalDb })
}

function Test-VmFrameworkTools {
    $framework = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8\mscorlib.dll'
    if (-not (Test-Path -LiteralPath $framework)) { throw '.NET Framework 4.8 Targeting Pack is missing.' }
    if (-not (Get-DotnetFrameworkBuildTools)) { throw 'MSBuild or the .NET Framework web build tools are missing.' }
    if (-not (Get-WorkshopIisExpress)) { throw 'IIS Express was not found.' }
    if (-not (Test-VmLocalDb)) { throw 'Could not verify the SQL Server LocalDB version.' }
    Write-WorkshopMessage '[PASS] Verified the .NET Framework 4.8 Targeting Pack, web build tools, IIS Express and LocalDB.'
    return $true
}

function Invoke-VmToolInstallation {
    $script:VmRestartRequired = $false
    if (Test-VmRebootPending) {
        Write-WorkshopMessage '[MANUAL] A Windows restart is pending. Restart manually and rerun this script.'
        return 3010
    }
    $drive = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':') -ErrorAction Stop
    if ($drive.Free -lt 50GB) { throw 'Free at least 50 GiB on the system drive before installation.' }
    $steps = @(
        @{ Group='[2/8] Windows features'; Name='WSL2 platform'; Run={ Install-VmWslPlatform } },
        @{ Name='Ubuntu WSL2'; Run={ Install-VmUbuntu } },
        @{ Name='MSMQ'; Run={ Install-VmMsmq } },
        @{ Group='[3/8] Runtimes and SDKs'; Name='Visual C++ x64 runtime'; Run={ Install-VmVisualCppRuntime } },
        @{ Name='.NET Framework'; Run={
            Install-VmPackage Microsoft.DotNet.Framework.Runtime '.NET Framework 4.8.x runtime' `
                -VersionPattern '^4\.8\.1$' -TestInstalled { Test-VmFrameworkRuntime }
        } },
        @{ Name='.NET 10 SDK'; Run={ Install-VmDotnetSdk 10 } },
        @{ Name='.NET 11 SDK'; Run={ Install-VmDotnetSdk 11 } },
        @{ Name='nvm and Node.js'; Run={ Install-VmNvm } },
        @{ Group='[4/8] .NET Framework build and run tools'; Name='Visual Studio Build Tools'; Run={
            Install-VmVisualStudio BuildTools (Join-Path $PSScriptRoot 'buildtools.vsconfig')
        } },
        @{ Name='IIS Express'; Run={ Install-VmIisExpress } },
        @{ Name='SQL Server LocalDB'; Run={ Install-VmLocalDb } },
        @{ Name='Framework build and run tools'; Run={ Test-VmFrameworkTools } },
        @{ Group='[5/8] Database and containers'; Name='PostgreSQL 18 client'; Run={ Install-VmPostgresClient } },
        @{ Name='Docker Desktop'; Run={
            Install-VmPackage Docker.DockerDesktop 'Docker Desktop (WSL2 backend)' -TestInstalled {
                Test-VmDesktopApp @((Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'))
            } -ExtraArguments @('--override', 'install --backend=wsl-2')
        } },
        @{ Group='[6/8] GitHub tools'; Name='Git'; Run={ Install-VmPackage Git.Git Git -TestInstalled { Test-VmCommand git } } },
        @{ Name='GitHub CLI'; Run={
            Install-VmPackage GitHub.cli 'GitHub CLI 2.45.0+' -TestInstalled {
                $probe = Invoke-ToolProbe gh @('--version')
                $probe.Code -eq 0 -and (Test-MinimumVersion $probe.Text '2.45.0')
            }
        } },
        @{ Name='GitHub Copilot CLI'; Run={
            Install-VmPackage GitHub.Copilot 'GitHub Copilot CLI' -TestInstalled { Test-VmCommand copilot }
        } },
        @{ Group='[7/8] Azure tools'; Name='Azure CLI'; Run={ Install-VmPackage Microsoft.AzureCLI 'Azure CLI' -TestInstalled { Test-VmCommand az } } },
        @{ Name='azd'; Run={ Install-VmPackage Microsoft.Azd azd -TestInstalled { Test-VmCommand azd @('version') } } },
        @{ Group='[8/8] Editors and modernization tools'; Name='VS Code'; Run={
            Install-VmPackage Microsoft.VisualStudioCode 'VS Code' -TestInstalled {
                Test-VmDesktopApp @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
                    (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe'))
            }
        } },
        @{ Name='GitHub Copilot app'; Run={ Install-VmCopilot } },
        @{ Name='Modernize CLI'; Run={
            Install-VmPackage GitHub.Copilot.modernization.agent 'Modernize CLI' -TestInstalled { Test-VmCommand modernize }
        } }
    )
    $failed = $false
    foreach ($step in $steps) {
        if ($step.ContainsKey('Group')) { Write-WorkshopMessage "[INFO] === $($step.Group) ===" }
        try {
            if (-not (& $step.Run)) { $failed = $true; Write-WorkshopMessage "[MANUAL] $($step.Name) is not ready." }
        }
        catch {
            $failed = $true
            Write-WorkshopMessage "[FAIL] $($step.Name): $($_.Exception.Message)"
        }
        if ($script:VmRestartRequired -or (Test-VmRebootPending)) {
            Write-WorkshopMessage '[MANUAL] A restart is required. The script does not restart automatically. Restart and rerun the same command.'
            return 3010
        }
    }
    Write-WorkshopMessage '[MANUAL] Set up the first Ubuntu user, start Docker Desktop and confirm Linux containers, sign in to the Copilot app, authenticate gh and Copilot CLI, and verify Modernize CLI.'
    Write-WorkshopMessage '[INFO] Azure/GitHub sign-in, subscription changes, provider registration and lab database creation were not performed.'
    if ($failed) { return 1 }
    Write-WorkshopMessage '[PASS] Verified the tool installations. Validate app builds and the VM runtime separately.'
    return 0
}

if ($MyInvocation.InvocationName -eq '.') {
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Dot-sourcing requires PowerShell 7. Run this script normally from Windows PowerShell 5.1.' }
}
elseif ($Help) {
    Write-Host 'Run from an elevated appmoduser terminal: powershell.exe -NoProfile -File "$HOME\scripts\install-vm-tools.ps1"'
    Write-Host 'Use -Yes to approve all tool installations, related license terms and installation settings in this interactive VM session.'
    Write-Host 'Without -Yes, each item requires consent. After a restart, rerun with the same options. No automatic sign-in or Azure deployment is performed.'
}
else {
    $ErrorActionPreference = 'Stop'
    try {
        $helpers = Get-VmHelperDirectory
        . (Join-Path $helpers 'powershell-bootstrap.ps1')
        Assert-VmInstallerContext
        $script:VmRestartRequired = $false
        if (Test-VmRebootPending) { Write-WorkshopMessage '[MANUAL] Restart manually and rerun this script.'; exit 3010 }
        Write-WorkshopMessage '[INFO] === [1/8] Installation prerequisites ==='
        if (-not (Initialize-VmWinget)) { Write-WorkshopMessage '[MANUAL] winget is not ready.'; exit 1 }
        if (-not (Install-VmPowerShell)) {
            if ($script:VmRestartRequired) { exit 3010 }
            exit 1
        }
        $bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{ Track='dotnet'; Yes=[bool]$Yes } `
            -RemainingArguments @() -AllowInstall
        if ($bootstrap.Handled) { exit $bootstrap.Code }
        if ($PSVersionTable.PSVersion.Major -ne 7) { throw 'Run this script in PowerShell 7.x.' }
        . (Join-Path $helpers 'install-prerequisites.ps1') -Track dotnet
        exit (Invoke-VmToolInstallation)
    }
    catch {
        Write-Error "[FAIL] $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
