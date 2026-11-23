. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\java-tools.ps1')
$script:Passed = 0
function Assert-Java([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}
$fixture = Join-Path $root ('.test-output\java-' + [guid]::NewGuid().ToString('N'))
$savedPath = $env:PATH
$savedJava = $env:JAVA_HOME
try {
    $null = [IO.Directory]::CreateDirectory($fixture)
    foreach ($major in @(8, 25)) {
        $bin = Join-Path $fixture "jdk-$major\bin"
        $null = [IO.Directory]::CreateDirectory($bin)
        Set-Content (Join-Path $bin 'java.exe') 'fixture'
        Set-Content (Join-Path $bin 'javac.exe') 'fixture'
    }
    & {
        $script:Mismatch = $false
        $script:ProbeFails = $false
        function Invoke-JavaVersionProbe {
            param($Executable)
            $version = if ($Executable -like '*jdk-8*') { '1.8.0_512' } else { '25.0.1' }
            if ($script:Mismatch -and $Executable -like '*javac.exe') { $version = '17.0.1' }
            $text = if ($Executable -like '*javac.exe') { "javac $version" } else { "openjdk version `"$version`"" }
            return [pscustomobject]@{ Code = $(if ($script:ProbeFails) { 1 } else { 0 }); Text = $text }
        }
        Assert-Java ((Find-WorkshopJava 8 -SearchRoots @($fixture) -RegistryRoots @()).Home -eq (Join-Path $fixture 'jdk-8')) 'JDK8 discovery validates both tools'
        Assert-Java ((Find-WorkshopJava 25 -SearchRoots @($fixture) -RegistryRoots @()).Home -eq (Join-Path $fixture 'jdk-25')) 'JDK25 discovery'
        $script:Mismatch = $true
        Assert-Java (-not (Find-WorkshopJava 25 -SearchRoots @($fixture) -RegistryRoots @())) 'mismatched javac rejected'
        $script:Mismatch = $false; $script:ProbeFails = $true
        Assert-Java (-not (Find-WorkshopJava 8 -SearchRoots @($fixture) -RegistryRoots @())) 'unrunnable JDK rejected'
    }
    Assert-Java (-not (Get-WorkshopJavaMajor 'openjdk version "25-ea"')) 'early access rejected'
    & {
        function Get-ChildItem {
            [CmdletBinding()]param($LiteralPath)
            Assert-Java ($LiteralPath -eq 'fixture-registry') 'injected registry root used'
            return [pscustomobject]@{ PSPath=(Join-Path $fixture 'registry-version') }
        }
        function Get-ItemProperty {
            [CmdletBinding()]param($LiteralPath,$Name)
            Assert-Java ($LiteralPath.EndsWith('hotspot\MSI') -and $Name -eq 'Path') 'Adoptium MSI Path queried'
            return [pscustomobject]@{ Path=(Join-Path $fixture 'jdk-8') }
        }
        function Invoke-JavaVersionProbe {
            param($Executable)
            $text = if ($Executable.EndsWith('javac.exe')) { 'javac 1.8.0_512' } else { 'openjdk version "1.8.0_512"' }
            return [pscustomobject]@{ Code=0; Text=$text }
        }
        Assert-Java ((Find-WorkshopJava 8 -SearchRoots @() -RegistryRoots @('fixture-registry')).Home -eq (Join-Path $fixture 'jdk-8')) 'registry-only JDK located'
    }
    & {
        . (Join-Path $root 'scripts\install-prerequisites.ps1') -Track java
        $script:Installed = $false; $script:Consent = $false; $script:Interactive = $true
        $script:InstallerCode = 0; $script:VerifyInstall = $true
        $script:JavaCalls = [Collections.Generic.List[string]]::new()
        $script:JavaPrompts = [Collections.Generic.List[string]]::new()
        $script:JavaInstalledVersion = '8.0.472.8'
        $script:JavaLatestVersion = '8.0.482.8'
        $script:JavaCatalogCode = 0
        function Test-WorkshopBootstrapInteractive { return $script:Interactive }
        function Find-WorkshopJava { param($Major); if ($script:Installed) { return [pscustomobject]@{ Home='fixture'; Major=$Major } } }
        function Get-Command { [CmdletBinding()]param($Name,$CommandType); return [pscustomobject]@{Source='fixture-winget'} }
        function Confirm-ToolInstall { param($Description); $script:JavaPrompts.Add($Description); return $script:Consent }
        function Invoke-ToolProbe {
            param($Name, $Arguments)
            $text = if ($Arguments[0] -eq 'list') { "$($Arguments[2]) $script:JavaInstalledVersion" }
                else { $script:JavaLatestVersion }
            return [pscustomobject]@{ Code=$script:JavaCatalogCode; Text=$text }
        }
        function winget {
            $script:JavaCalls.Add(($args -join ' '))
            $script:Installed = $script:VerifyInstall
            $global:LASTEXITCODE = $script:InstallerCode
        }
        Assert-Java (Install-WorkshopJava 8) 'decline defers to final check'
        Assert-Java ($script:JavaCalls.Count -eq 0) 'decline has no side effects'
        $script:Consent = $true; $script:Interactive = $false
        Assert-Java (-not (Install-WorkshopJava 8)) 'noninteractive install denied'
        Assert-Java ($script:JavaCalls.Count -eq 0) 'noninteractive install has no side effects'
        $script:Interactive = $true
        Assert-Java (Install-WorkshopJava 8) 'approved Java install'
        Assert-Java ($script:JavaCalls[0] -eq 'install --id EclipseAdoptium.Temurin.8.JDK --exact --source winget --custom ADDLOCAL=FeatureMain') 'only FeatureMain requested'
        Assert-Java (Install-WorkshopJava 8) 'existing JDK retained'
        Assert-Java ($script:JavaCalls.Count -eq 1) 'no implicit JDK update'
        Assert-Java (Install-WorkshopJava 8 -Update) 'explicit update'
        Assert-Java ($script:JavaCalls[-1] -like 'upgrade --id EclipseAdoptium.Temurin.8.JDK*') 'update selects exact major'
        $prompts = $script:JavaPrompts.Count; $calls = $script:JavaCalls.Count
        $script:JavaInstalledVersion = $script:JavaLatestVersion
        Assert-Java (Install-WorkshopJava 8 -Update) 'current JDK package retained'
        $script:JavaInstalledVersion = '8.0.492.8'
        Assert-Java (Install-WorkshopJava 8 -Update) 'newer JDK package retained'
        Assert-Java ($script:JavaPrompts.Count -eq $prompts -and $script:JavaCalls.Count -eq $calls) 'current and newer JDK packages never prompt or upgrade'
        $script:JavaCatalogCode = 1; $script:Consent = $false
        Assert-Java (Install-WorkshopJava 8 -Update) 'unknown JDK metadata can be declined'
        Assert-Java ($script:JavaPrompts.Count -eq $prompts + 1 -and $script:JavaCalls.Count -eq $calls) 'unverified metadata never silently authorizes an update'
        $script:JavaCatalogCode = 0; $script:Consent = $true
        $script:Installed=$false; $script:VerifyInstall=$false
        Assert-Java (-not (Install-WorkshopJava 25)) 'successful installer without JDK fails verification'
        $script:InstallerCode=1
        Assert-Java (-not (Install-WorkshopJava 25)) 'installer failure propagated'
    }
    if ($IsWindows) {
        $scripts = Join-Path $fixture 'scripts'
        $null = [IO.Directory]::CreateDirectory($scripts)
        Copy-Item (Join-Path $root 'scripts\use-java.ps1') $scripts
        # Isolated helper replaces only JDK discovery, not selector behavior.
        Set-Content (Join-Path $scripts 'java-tools.ps1') @'
function Find-WorkshopJava {
    param($Major)
    if ($env:FIXTURE_JAVA_MISSING -eq '1') { return }
    [pscustomobject]@{ Home="C:\fixture\jdk-$Major"; RuntimeVersion="$Major"; CompilerVersion="$Major" }
}
'@
        Push-Location $fixture
        try {
            $selector = Join-Path $scripts 'use-java.ps1'
            $failed=$false
            try { . $selector -Jdk 8 } catch { $failed=$true }
            Assert-Java $failed 'requires app root'
            Set-Content '.\mvnw.cmd' 'fixture'
            . $selector -Jdk 8
            . $selector -Jdk 25
            . $selector -Jdk 25
            Assert-Java ($env:JAVA_HOME -eq 'C:\fixture\jdk-25') 'session JDK switched'
            Assert-Java (@($env:PATH -split ';' | Where-Object { $_ -eq 'C:\fixture\jdk-25\bin' }).Count -eq 1) 'PATH does not accumulate'
            Assert-Java ($env:PATH -notlike '*C:\fixture\jdk-8\bin*') 'previous selected JDK removed'
            $failed=$false
            try { . $selector -Jdk 17 } catch { $failed=$true }
            Assert-Java $failed 'invalid JDK fails without exiting caller'
            $env:FIXTURE_JAVA_MISSING='1'
            $failed=$false
            try { . $selector -Jdk 8 } catch { $failed=$true }
            Assert-Java $failed 'missing JDK fails without changing selection'
            Assert-Java ($env:JAVA_HOME -eq 'C:\fixture\jdk-25') 'failure preserves Java selection'
            Remove-Item Env:\FIXTURE_JAVA_MISSING
            & pwsh -NoProfile -File $selector -Jdk 8 2>&1 | Out-Null
            Assert-Java ($LASTEXITCODE -eq 2) 'direct invocation rejected'
            $legacy = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $command = "try { . '$($selector.Replace("'","''"))' -Jdk 8 } catch { Write-Output 'EXPECTED_ERROR' }; Write-Output 'CALLER_ALIVE'"
            $output = & $legacy -NoProfile -NonInteractive -Command $command 2>&1 | Out-String
            Assert-Java ($LASTEXITCODE -eq 0 -and $output.Contains('EXPECTED_ERROR') -and $output.Contains('CALLER_ALIVE')) '5.1 dot-source rejects and caller survives'
        }
        finally { Pop-Location }
    }
    Write-Host "PASS: $script:Passed Java PowerShell assertions"
}
finally {
    $env:PATH = $savedPath
    $env:JAVA_HOME = $savedJava
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
