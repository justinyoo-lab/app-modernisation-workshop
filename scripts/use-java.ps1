param([string]$Jdk)

if ($MyInvocation.InvocationName -ne '.') {
    Write-Error 'Dot-source from the app root: . ../scripts/use-java.ps1 -Jdk 8|25'
    exit 2
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Dot-source in PowerShell 7 to switch Java in the current shell. Windows PowerShell 5.1 cannot update the caller environment.'
}

& {
    param($Major, $Scripts)
    if ($Major -cnotin @('8', '25')) { throw '-Jdk must be 8 or 25.' }
    if (-not (Test-Path -LiteralPath '.\mvnw.cmd' -PathType Leaf)) { throw 'Run from the sample app root. The current directory has no mvnw.cmd.' }
    . (Join-Path $Scripts 'java-tools.ps1')
    $jdk = Find-WorkshopJava -Major ([int]$Major)
    if (-not $jdk) { throw "Could not find working java and javac for Temurin JDK $Major. Check the installation path and version." }
    $oldBin = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin' } else { '' }
    $newBin = Join-Path $jdk.Home 'bin'
    $remaining = @($env:PATH -split ';' | Where-Object { $_ -and $_.TrimEnd('\', '/') -ine $oldBin -and $_.TrimEnd('\', '/') -ine $newBin })
    $env:JAVA_HOME = $jdk.Home
    $env:PATH = (@($newBin) + $remaining) -join ';'
    Write-WorkshopMessage "[PASS] Selected Temurin JDK $Major`: $($jdk.Home)"
    Write-Host $jdk.RuntimeVersion
    Write-Host $jdk.CompilerVersion
} $Jdk $PSScriptRoot
