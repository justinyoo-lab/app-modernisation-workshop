[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\.generated\payload.json')
)

function Get-VmPayloadSources {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $sources = [ordered]@{}
    foreach ($name in @('powershell-bootstrap.ps1', 'install-prerequisites.ps1', 'windows-prerequisite-updates.ps1',
            'check-prerequisites.ps1', 'dotnet-framework-tools.ps1', 'java-tools.ps1')) {
        $sources[$name] = Join-Path $root "scripts\$name"
    }
    foreach ($name in @('install-vm-tools.ps1', 'buildtools.vsconfig')) {
        $sources[$name] = Join-Path $PSScriptRoot $name
    }
    return $sources
}

function New-VmPayload {
    param([System.Collections.IDictionary]$Sources)
    $files = foreach ($name in $Sources.Keys) {
        [ordered]@{ name = $name; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Sources[$name])) }
    }
    $json = [ordered]@{ schemaVersion = 1; files = @($files) } | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    if ($bytes.Length -gt 1048576) { throw 'VM script payload exceeds the 1 MiB uncompressed limit.' }
    $stream = New-Object IO.MemoryStream
    $gzip = New-Object IO.Compression.GZipStream($stream, [IO.Compression.CompressionMode]::Compress, $true)
    try { $gzip.Write($bytes, 0, $bytes.Length) }
    finally { $gzip.Dispose() }
    try { $content = [Convert]::ToBase64String($stream.ToArray()) }
    finally { $stream.Dispose() }
    if ($content.Length -gt 90000) { throw 'Compressed VM payload is too large for inline delivery.' }
    return [ordered]@{ content = $content }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    try {
        $payload = New-VmPayload -Sources (Get-VmPayloadSources)
        $target = [IO.Path]::GetFullPath($OutputPath)
        $null = [IO.Directory]::CreateDirectory((Split-Path $target -Parent))
        [IO.File]::WriteAllText($target, ($payload | ConvertTo-Json -Compress) + "`n", [Text.UTF8Encoding]::new($false))
        Write-Host "[PASS] VM script payload: $($payload.content.Length) base64 characters."
    }
    catch {
        Write-Error "VM script packaging failed: $($_.Exception.Message)"
        exit 1
    }
}
