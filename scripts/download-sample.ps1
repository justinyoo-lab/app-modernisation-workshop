[CmdletBinding()]
param(
    [string]$Track,
    [string]$Destination,
    [string]$ContainerEngine,
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$script:DownloadScripts = $PSScriptRoot

function Get-SampleDefinition {
    param([string]$SelectedTrack)
    switch -CaseSensitive ($SelectedTrack) {
        'java' { return [pscustomobject]@{ Repository = 'https://github.com/Azure-Samples/java-migration-copilot-samples.git'; Commit = '317d3bbfd61fb1e402bea61f90e385bec12f2070'; Subdirectory = 'asset-manager'; Required = @('pom.xml', 'web', 'worker', 'mvnw', 'mvnw.cmd', '.mvn\wrapper\maven-wrapper.properties') } }
        'dotnet' { return [pscustomobject]@{ Repository = 'https://github.com/Azure-Samples/dotnet-migration-copilot-samples.git'; Commit = '7c1bf47b7e2627fe5a1c764716638815d35e0282'; Subdirectory = 'ContosoUniversity'; Required = @('ContosoUniversity.sln', 'ContosoUniversity.csproj', 'packages.config') } }
        default { throw [ArgumentException]::new('Specify -Track java or dotnet.') }
    }
}

function Assert-SafeDestination {
    param([string]$Path, [string]$WorkshopRoot)
    if ($IsWindows -and ($Path.StartsWith('\\?\') -or $Path.StartsWith('\\.\'))) {
        throw 'Windows extended/device paths are not supported. Use a standard drive path.'
    }
    $full = [IO.Path]::GetFullPath($Path, (Get-Location).ProviderPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\', '/')
    if (-not $full -or $full -eq $root -or $full -eq $HOME.TrimEnd('\', '/') -or $full -eq $WorkshopRoot.TrimEnd('\', '/')) {
        throw 'The home directory, drive root, and workshop root cannot be download destinations.'
    }
    foreach ($name in @('docs', 'scripts', 'tests')) {
        $protected = [IO.Path]::GetFullPath((Join-Path $WorkshopRoot $name)).TrimEnd('\', '/')
        if ($full -eq $protected -or $full.StartsWith($protected + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Apps cannot be downloaded into workshop material directories.'
        }
    }
    $ancestor = $full
    while ($ancestor) {
        $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Destinations reached through symbolic links or junctions are not supported.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (Test-Path -LiteralPath $full) {
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'The destination is not a directory.' }
        if (@(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop).Count -gt 0) { throw 'The destination directory is not empty. Existing files will not be overwritten.' }
    }
    return $full
}

function Invoke-DownloadGit {
    param([string[]]$Arguments)
    & git @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Git command failed (exit code $LASTEXITCODE). Check network access, Git settings, and destination permissions." }
}

function Invoke-SampleDownload {
    param([string]$Target, $Definition, [string]$WorkshopRoot)
    $targetPath = Assert-SafeDestination $Target $WorkshopRoot
    $parent = [IO.Path]::GetDirectoryName($targetPath)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $staging = Join-Path $parent ('.workshop-download-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    try {
        $checkout = Join-Path $staging 'checkout'
        Invoke-DownloadGit @('init', '--quiet', $checkout)
        Invoke-DownloadGit @('-C', $checkout, 'remote', 'add', 'origin', $Definition.Repository)
        Invoke-DownloadGit @('-C', $checkout, 'fetch', '--quiet', '--depth', '1', 'origin', $Definition.Commit)
        Invoke-DownloadGit @('-C', $checkout, '-c', 'advice.detachedHead=false', '-c', 'core.autocrlf=false', 'checkout', '--quiet', '--detach', 'FETCH_HEAD')
        $head = (& git -C $checkout rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -cne $Definition.Commit) { throw 'Upstream commit verification failed.' }
        $source = Join-Path $checkout $Definition.Subdirectory
        foreach ($required in $Definition.Required) {
            if (-not (Test-Path -LiteralPath (Join-Path $source $required))) { throw "Required upstream path is missing: $required" }
        }
        $payload = Join-Path $staging 'payload'
        [IO.Directory]::CreateDirectory($payload) | Out-Null
        Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $payload -Recurse -Force -ErrorAction Stop
        $metadataPath = Join-Path $payload 'upstream-source.json'
        if (Test-Path -LiteralPath $metadataPath) { throw 'The upstream source contains upstream-source.json. Stopping without overwriting the provenance file.' }
        $licensePresent = $false
        $noticePattern = '^(LICENSE|LICENCE|NOTICE|COPYING|COPYRIGHT)([._-].*)?$'
        foreach ($notice in Get-ChildItem -LiteralPath $checkout -Force -File | Where-Object Name -Match $noticePattern) {
            $noticePath = Join-Path $payload ("UPSTREAM-" + $notice.Name)
            if (Test-Path -LiteralPath $noticePath) { throw "An upstream file conflicts with the preserved notice path: $($notice.Name)" }
            Copy-Item -LiteralPath $notice.FullName -Destination $noticePath -ErrorAction Stop
            if ($notice.Name -match '^(LICENSE|LICENCE|COPYING)([._-].*)?$') { $licensePresent = $true }
        }
        if (Get-ChildItem -LiteralPath $source -Force -File | Where-Object Name -Match '^(LICENSE|LICENCE|COPYING)([._-].*)?$') { $licensePresent = $true }
        $metadata = [ordered]@{ repository = $Definition.Repository; commit = $Definition.Commit; subdirectory = $Definition.Subdirectory; licenseFileFound = $licensePresent }
        $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8 -ErrorAction Stop
        $null = Assert-SafeDestination $targetPath $WorkshopRoot
        if (Test-Path -LiteralPath $targetPath) { [IO.Directory]::Delete($targetPath, $false) }
        [IO.Directory]::Move($payload, $targetPath)
        Write-WorkshopMessage "[PASS] Sample downloaded: $targetPath"
        Write-WorkshopMessage "[PASS] Upstream commit: $head / No Git repository created in the app directory"
        if (-not $licensePresent) { Write-WorkshopMessage '[WARN] No upstream license file was found. Do not assume permission to redistribute.' }
    }
    finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
    }
}

function Invoke-DownloadMain {
    if ($Help) {
        Write-Host './scripts/download-sample.ps1 -Track java|dotnet [-Destination PATH] [-ContainerEngine docker|podman]'
        return 0
    }
    if ($Track -cnotin @('java', 'dotnet')) { Write-WorkshopMessage '[FAIL] Specify -Track java or -Track dotnet.'; return 2 }
    if (-not $IsWindows) { Write-WorkshopMessage '[FAIL] PowerShell entrypoints are Windows-only. For the Java track, run ./scripts/download-sample.sh.'; return 1 }
    $definition = Get-SampleDefinition $Track
    $workshop = Split-Path $script:DownloadScripts -Parent
    $savedHelp = $Help
    . (Join-Path $script:DownloadScripts 'check-prerequisites.ps1') -Track $Track -ContainerEngine $ContainerEngine
    $Help = $savedHelp
    try {
        $destinationPath = if ($Destination) { [IO.Path]::GetFullPath($Destination, (Get-Location).ProviderPath) } else { Join-Path $workshop $Track }
        $engine = Resolve-ContainerEngine $ContainerEngine
        $null = Assert-SafeDestination $destinationPath $workshop
    }
    catch { Write-WorkshopMessage "[FAIL] $($_.Exception.Message)"; return 2 }
    $preflightCode = Invoke-WorkshopPowerShell -ScriptPath (Join-Path $script:DownloadScripts 'check-prerequisites.ps1') -BoundParameters @{ Track = $Track; ContainerEngine = $engine } -RemainingArguments @()
    if ($preflightCode -ne 0) { Write-WorkshopMessage '[FAIL] Prerequisite checks did not pass. Nothing was downloaded.'; return 1 }
    try {
        Invoke-SampleDownload $destinationPath $definition $workshop
        return 0
    }
    catch { Write-WorkshopMessage "[FAIL] Download failed: $($_.Exception.Message)"; return 1 }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-DownloadMain) }
