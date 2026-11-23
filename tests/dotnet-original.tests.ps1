. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\run-dotnet-original.ps1')
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:passed++
}
$fixture = Join-Path $root ('.test-output\original-' + [guid]::NewGuid().ToString('N'))
$savedProgramFiles = $env:ProgramFiles
$savedProgramFilesX86 = ${env:ProgramFiles(x86)}
try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    $AppPath = Join-Path $fixture 'app with spaces & unicode 한글'
    [IO.Directory]::CreateDirectory($AppPath) | Out-Null
    Set-Content (Join-Path $AppPath 'ContosoUniversity.csproj') '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><TargetFrameworkVersion>v4.8</TargetFrameworkVersion></PropertyGroup></Project>'
    foreach ($file in @('ContosoUniversity.sln', 'packages.config', 'Web.config')) { Set-Content (Join-Path $AppPath $file) 'fixture' }
    $originalConfig = Get-Content (Join-Path $AppPath 'Web.config') -Raw
    $env:ProgramFiles = Join-Path $fixture 'program files'
    ${env:ProgramFiles(x86)} = Join-Path $fixture 'program files x86'
    $vs = Join-Path $fixture 'build tools'
    $msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
    $targets = Join-Path $vs 'MSBuild\Microsoft\VisualStudio\v18.0\WebApplications\Microsoft.WebApplication.targets'
    $iis = Join-Path $env:ProgramFiles 'IIS Express\iisexpress.exe'
    $template = Join-Path $env:ProgramFiles 'IIS Express\AppServer\applicationhost.config'
    foreach ($file in @($msbuild, $targets, $iis, $template)) {
        [IO.Directory]::CreateDirectory((Split-Path $file -Parent)) | Out-Null
        Set-Content $file 'fixture'
    }
    $templateXml = @'
<configuration>
 <system.applicationHost>
  <applicationPools><add name="OldPool" managedRuntimeVersion="v4.0" managedPipelineMode="Integrated" CLRConfigFile="%IIS_BIN%\fixture.config" /><applicationPoolDefaults managedRuntimeVersion="v4.0" /></applicationPools>
  <sites><site name="OldSite" /></sites>
 </system.applicationHost>
 <system.webServer>
  <modules><add name="PreservedModule" /></modules>
  <security><authentication>
   <anonymousAuthentication enabled="true" />
   <windowsAuthentication enabled="false"><providers><add value="Negotiate" /><add value="NTLM" /></providers></windowsAuthentication>
  </authentication></security>
 </system.webServer>
</configuration>
'@
    Set-Content $template $templateXml
    $script:discovery = @(
        @{ installationVersion='18.1.0'; installationPath=(Join-Path $fixture 'incomplete newer instance') },
        @{ installationVersion='18.0.1'; installationPath=$vs }
    ) | ConvertTo-Json
    function Invoke-FrameworkProbe {
        param($File, $Arguments)
        Assert-True ($Arguments -contains '*') 'discovery includes Build Tools'
        return [pscustomobject]@{ Code=0; Text=$script:discovery }
    }
    Assert-True ((Get-DotnetFrameworkBuildTools).MSBuild -eq $msbuild) 'skip incomplete newest installation'
    $script:calls = [Collections.Generic.List[object]]::new()
    $script:failOn = ''
    function Invoke-OriginalTool {
        param([string]$File, [string[]]$Arguments)
        $script:calls.Add([pscustomobject]@{ File=$File; Arguments=$Arguments; Directory=(Get-Location).Path })
        if ($script:failOn -and $Arguments -contains $script:failOn) { throw 'fixture native failure' }
    }
    if ($IsWindows) {
        $Help=$false; $Run=$false; $AllowDatabaseInitialization=$false; $Configuration='Debug'; $Port=58801
        Assert-True ((Invoke-OriginalMain) -eq 0) 'build-only succeeds'
        Assert-True ($script:calls.Count -eq 2) 'default never launches IIS or probes HTTP'
        Assert-True ($script:calls[0].Arguments -contains '/t:Restore') 'restore first'
        Assert-True ($script:calls[0].Arguments -contains '/p:RestorePackagesConfig=true') 'packages.config restore'
        Assert-True ($script:calls[0].Arguments -contains "/p:RestoreRepositoryPath=$(Join-Path $AppPath 'packages')") 'restore to upstream hint path'
        Assert-True ($script:calls[1].Arguments -contains '/t:Build') 'build second'
        Assert-True ($script:calls[1].Arguments -contains "/p:VSToolsPath=$(Split-Path (Split-Path $targets -Parent) -Parent)") 'explicit web tools'
        Assert-True ($script:calls[1].Arguments[0] -eq (Join-Path $AppPath 'ContosoUniversity.sln')) 'solution path remains one argument'
        Assert-True ($script:calls[1].Directory -eq $AppPath) 'commands run in actual app directory'
        $Run=$true
        $script:calls.Clear()
        Assert-True ((Invoke-OriginalMain) -eq 1) 'run requires DB acknowledgement'
        Assert-True ($script:calls.Count -eq 0) 'blocked run has no side effects'
        $AllowDatabaseInitialization=$true
        $script:failOn='/t:Restore'
        Assert-True ((Invoke-OriginalMain) -eq 1) 'restore failure propagates'
        Assert-True ($script:calls.Count -eq 1) 'restore failure prevents build and run'
        $script:calls.Clear(); $script:failOn='/t:Build'
        Assert-True ((Invoke-OriginalMain) -eq 1) 'build failure propagates'
        Assert-True ($script:calls.Count -eq 2) 'build failure prevents IIS'
        $script:calls.Clear(); $script:failOn=''
        Assert-True ((Invoke-OriginalMain) -eq 0) 'mocked run succeeds'
        Assert-True ($script:calls.Count -eq 3) 'IIS called only after restore and build'
        Assert-True ($script:calls[2].File -eq $iis) 'installed IIS path used'
        $configPath = ($script:calls[2].Arguments | Where-Object { $_ -like '/config:*' }).Substring(8)
        [xml]$config = Get-Content -LiteralPath $configPath -Raw
        $site = $config.configuration.'system.applicationHost'.sites.site
        Assert-True ($site.application.virtualDirectory.physicalPath -eq $AppPath) 'XML escapes app path'
        Assert-True ($site.bindings.binding.bindingInformation -eq '*:58801:localhost') 'localhost-only HTTP host binding'
        Assert-True ($config.configuration.'system.applicationHost'.applicationPools.add.managedRuntimeVersion -eq 'v4.0') 'CLR4 integrated pool'
        Assert-True ($config.configuration.'system.applicationHost'.applicationPools.add.CLRConfigFile -eq '%IIS_BIN%\fixture.config') 'installed ASP.NET CLR configuration retained'
        Assert-True ($config.configuration.'system.applicationHost'.applicationPools.add.processModel.loadUserProfile -eq 'true') 'LocalDB user profile retained'
        Assert-True ($config.configuration.'system.applicationHost'.applicationPools.applicationPoolDefaults.managedRuntimeVersion -eq 'v4.0') 'installed pool defaults retained'
        Assert-True ($config.configuration.'system.webServer'.security.authentication.windowsAuthentication.enabled -eq 'true') 'upstream Windows authentication preserved'
        Assert-True ($config.configuration.'system.webServer'.security.authentication.anonymousAuthentication.enabled -eq 'false') 'anonymous auth disabled'
        Assert-True ($config.configuration.'system.webServer'.modules.add.name -eq 'PreservedModule') 'installed modules preserved'
        Assert-True ((Get-Content $template -Raw).Trim() -eq $templateXml.Trim()) 'global template untouched'
        Assert-True ((Get-Content (Join-Path $AppPath 'Web.config') -Raw) -eq $originalConfig) 'Web.config unchanged'
        $script:calls.Clear()
        $script:failOn='/site:WorkshopOriginal'
        Assert-True ((Invoke-OriginalMain) -eq 1) 'IIS failure propagates'
        $script:failOn=''; $script:calls.Clear()
        Set-Content (Join-Path $AppPath 'ContosoUniversity.csproj') '<Project><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
        Assert-True ((Invoke-OriginalMain) -eq 1) 'modernized project rejected'
        Assert-True ($script:calls.Count -eq 0) 'modernized project never builds with legacy helper'
        Set-Content (Join-Path $AppPath 'ContosoUniversity.csproj') '<Project><PropertyGroup><TargetFrameworkVersion>v4.8</TargetFrameworkVersion></PropertyGroup></Project>'
        Remove-Item (Join-Path $AppPath 'packages.config')
        Assert-True ((Invoke-OriginalMain) -eq 1) 'missing original files fail closed'
        Assert-True ($script:calls.Count -eq 0) 'invalid original cannot build or run'
        $installedTemplate = Join-Path $savedProgramFiles 'IIS Express\AppServer\applicationhost.config'
        if (Test-Path -LiteralPath $installedTemplate) {
            $generated = Join-Path $fixture 'installed-template-result.config'
            New-OriginalIisConfig $installedTemplate $AppPath 58802 $generated
            [xml]$installedResult = Get-Content $generated -Raw
            Assert-True ($installedResult.configuration.'system.applicationHost'.sites.site.bindings.binding.bindingInformation -eq '*:58802:localhost') 'real installed IIS template transforms without starting IIS'
            Assert-True ($installedResult.configuration.'system.applicationHost'.applicationPools.add.CLRConfigFile -like '*aspnet.config') 'real installed CLR configuration retained'
        }
    }
    else { Write-Host 'SKIP Windows CLI orchestration fixtures on non-Windows.' }
    Write-Host "PASS: $script:passed assertions (isolated fixtures; no real build, IIS, HTTP or database operations)."
}
finally {
    $env:ProgramFiles = $savedProgramFiles
    ${env:ProgramFiles(x86)} = $savedProgramFilesX86
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
