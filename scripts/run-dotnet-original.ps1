[CmdletBinding()]
param(
    [string]$AppPath,
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateRange(1024, 65535)][int]$Port = 58801,
    [switch]$Run,
    [switch]$AllowDatabaseInitialization,
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }
if (-not $PSBoundParameters.ContainsKey('AppPath')) { $AppPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'dotnet' }

. (Join-Path $PSScriptRoot 'dotnet-framework-tools.ps1')

function Invoke-OriginalTool {
    param([string]$File, [string[]]$Arguments)
    & $File @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit code $LASTEXITCODE): $File" }
}

function New-OriginalIisConfig {
    param([string]$Template, [string]$ApplicationPath, [int]$ListenPort, [string]$OutputPath)
    [xml]$config = Get-Content -LiteralPath $Template -Raw -ErrorAction Stop
    $sites = $config.SelectSingleNode('/configuration/system.applicationHost/sites')
    $pools = $config.SelectSingleNode('/configuration/system.applicationHost/applicationPools')
    if ($null -eq $sites -or $null -eq $pools) { throw 'The IIS Express template has no sites/applicationPools.' }
    $sites.RemoveAll()
    $installedPool = $pools.SelectSingleNode('add[@managedRuntimeVersion="v4.0" and @managedPipelineMode="Integrated"]')
    $pool = if ($null -ne $installedPool) { $installedPool.CloneNode($true) } else { $config.CreateElement('add') }
    foreach ($oldPool in @($pools.SelectNodes('add'))) { $null = $pools.RemoveChild($oldPool) }
    foreach ($entry in @{ name='WorkshopPool'; managedRuntimeVersion='v4.0'; managedPipelineMode='Integrated' }.GetEnumerator()) {
        $pool.SetAttribute($entry.Key, $entry.Value)
    }
    $profile = $pool.SelectSingleNode('processModel')
    if ($null -eq $profile) {
        $profile = $config.CreateElement('processModel')
        $null = $pool.AppendChild($profile)
    }
    $profile.SetAttribute('loadUserProfile', 'true')
    $profile.SetAttribute('setProfileEnvironment', 'false')
    $null = $pools.AppendChild($pool)
    $site = $config.CreateElement('site')
    $site.SetAttribute('name', 'WorkshopOriginal')
    $site.SetAttribute('id', '1')
    $site.SetAttribute('serverAutoStart', 'true')
    $app = $config.CreateElement('application')
    $app.SetAttribute('path', '/')
    $app.SetAttribute('applicationPool', 'WorkshopPool')
    $directory = $config.CreateElement('virtualDirectory')
    $directory.SetAttribute('path', '/')
    $directory.SetAttribute('physicalPath', $ApplicationPath)
    $null = $app.AppendChild($directory)
    $null = $site.AppendChild($app)
    $bindings = $config.CreateElement('bindings')
    $binding = $config.CreateElement('binding')
    $binding.SetAttribute('protocol', 'http')
    $binding.SetAttribute('bindingInformation', "*:${ListenPort}:localhost")
    $null = $bindings.AppendChild($binding)
    $null = $site.AppendChild($bindings)
    $null = $sites.AppendChild($site)
    # Keep the project's IIS Express Windows authentication settings without changing Web.config.
    $authentication = $config.configuration.'system.webServer'.security.authentication
    if (-not $authentication.anonymousAuthentication -or -not $authentication.windowsAuthentication) {
        throw 'The IIS Express template has no Windows/anonymous authentication configuration.'
    }
    $authentication.anonymousAuthentication.SetAttribute('enabled', 'false')
    $authentication.windowsAuthentication.SetAttribute('enabled', 'true')
    $config.Save($OutputPath)
}

function Invoke-OriginalMain {
    if ($Help) {
        Write-Host 'pwsh -File scripts\run-dotnet-original.ps1 [-AppPath PATH] [-Configuration Debug|Release] [-Run -AllowDatabaseInitialization] [-Port 58801]'
        Write-Host 'By default, this script only restores and builds. -Run starts IIS Express in the foreground; the first HTTP request may initialize the database.'
        return 0
    }
    try {
        if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'Run in PowerShell 7 on Windows.' }
        if ($Run -and -not $AllowDatabaseInitialization) { throw 'Review Web.config and Data\DbInitializer.cs, confirm that the database is dedicated to this workshop, then specify -AllowDatabaseInitialization.' }
        $path = (Resolve-Path -LiteralPath $AppPath -ErrorAction Stop).ProviderPath
        foreach ($file in @('ContosoUniversity.sln', 'ContosoUniversity.csproj', 'packages.config', 'Web.config')) {
            if (-not (Test-Path -LiteralPath (Join-Path $path $file) -PathType Leaf)) { throw "Required original sample file is missing: $file" }
        }
        [xml]$project = Get-Content -LiteralPath (Join-Path $path 'ContosoUniversity.csproj') -Raw
        if ($project.Project.PropertyGroup.TargetFrameworkVersion -notcontains 'v4.8') { throw 'This helper supports only the original net48 sample before modernization.' }
        $tools = Get-DotnetFrameworkBuildTools
        $properties = @("/p:Configuration=$Configuration", "/p:VisualStudioVersion=$($tools.Version)", "/p:VSToolsPath=$($tools.WebTools)")
        $solution = Join-Path $path 'ContosoUniversity.sln'
        Push-Location $path
        try {
            Invoke-OriginalTool $tools.MSBuild (@($solution, '/t:Restore', '/p:RestorePackagesConfig=true', "/p:RestoreRepositoryPath=$(Join-Path $path 'packages')", '/nologo') + $properties)
            Invoke-OriginalTool $tools.MSBuild (@($solution, '/t:Build', '/nologo') + $properties)
            if (-not $Run) { return 0 }
            $iis = Get-WorkshopIisExpress
            $state = Join-Path $path '.vs\workshop'
            [IO.Directory]::CreateDirectory($state) | Out-Null
            $configPath = Join-Path $state ("applicationhost-" + [guid]::NewGuid().ToString('N') + '.config')
            New-OriginalIisConfig $iis.Template $path $Port $configPath
            Write-Host "Running IIS Express in the foreground: http://localhost:$Port/ (stop: Q or Ctrl+C). Verify the target database before the first request."
            Invoke-OriginalTool $iis.Exe @("/config:$configPath", '/site:WorkshopOriginal', '/systray:false')
            return 0
        }
        finally { Pop-Location }
    }
    catch { Write-WorkshopMessage "[FAIL] $($_.Exception.Message)"; return 1 }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-OriginalMain) }
