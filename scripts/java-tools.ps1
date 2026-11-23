. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

function Invoke-JavaVersionProbe {
    param([string]$Executable)
    try {
        $text = (& $Executable -version 2>&1 | Out-String).Trim()
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
    }
    catch { return [pscustomobject]@{ Code = 126; Text = $_.Exception.Message } }
}

function Get-WorkshopJavaMajor {
    param([string]$Text, [switch]$Compiler)
    if ($Text -match '-ea\b') { return }
    $pattern = if ($Compiler) { '(?m)^javac\s+(?:1\.)?(\d+)(?:[.\s]|$)' }
        else { '(?m)^(?:openjdk|java) version "(?:1\.)?(\d+)(?:[."]|$)' }
    if ($Text -match $pattern) { return [int]$Matches[1] }
}

function Find-WorkshopJava {
    param(
        [int]$Major,
        [string[]]$SearchRoots = @("$env:ProgramFiles\Eclipse Adoptium"),
        [string[]]$RegistryRoots = @('HKLM:\SOFTWARE\Eclipse Adoptium\JDK', 'HKCU:\SOFTWARE\Eclipse Adoptium\JDK')
    )
    $candidates = @()
    foreach ($root in $RegistryRoots) {
        foreach ($version in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $entry = Get-ItemProperty -LiteralPath (Join-Path $version.PSPath 'hotspot\MSI') -Name Path -ErrorAction SilentlyContinue
            if ($entry.Path) { $candidates += $entry.Path }
        }
    }
    foreach ($root in $SearchRoots) {
        $candidates += @(Get-ChildItem -LiteralPath $root -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -ExpandProperty FullName)
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $java = Join-Path $candidate 'bin\java.exe'
        $javac = Join-Path $candidate 'bin\javac.exe'
        if (-not (Test-Path -LiteralPath $java -PathType Leaf) -or -not (Test-Path -LiteralPath $javac -PathType Leaf)) { continue }
        $runtime = Invoke-JavaVersionProbe $java
        $compiler = Invoke-JavaVersionProbe $javac
        if ($runtime.Code -eq 0 -and $compiler.Code -eq 0 -and
            (Get-WorkshopJavaMajor $runtime.Text) -eq $Major -and
            (Get-WorkshopJavaMajor $compiler.Text -Compiler) -eq $Major) {
            return [pscustomobject]@{
                Home = [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
                Java = $java; Javac = $javac; RuntimeVersion = $runtime.Text; CompilerVersion = $compiler.Text
            }
        }
    }
}
