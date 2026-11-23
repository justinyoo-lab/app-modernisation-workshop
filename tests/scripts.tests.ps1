. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\check-prerequisites.ps1')
. (Join-Path $root 'scripts\download-sample.ps1')
$script:Passed = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}
function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-True $threw $Name
}
function New-Results { $script:CheckResults = [Collections.Generic.List[object]]::new() }
function Has-Failure([string]$Id) { return @($script:CheckResults | Where-Object { $_.Id -eq $Id -and $_.Status -eq 'FAIL' }).Count -gt 0 }

$temporary = Join-Path $root ('.test-output\ps-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temporary) | Out-Null
$savedEngine = $env:AZD_CONTAINER_RUNTIME
$savedProgramFiles = $env:ProgramFiles
$savedProgramFilesX86 = ${env:ProgramFiles(x86)}
try {
    foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "syntax $($file.Name)"
        $koreanStrings = @($ast.FindAll({
            param($node)
            ($node -is [Management.Automation.Language.StringConstantExpressionAst] -or
                $node -is [Management.Automation.Language.ExpandableStringExpressionAst]) -and
                $node.Extent.Text -match '[\uac00-\ud7a3]'
        }, $true))
        Assert-True ($koreanStrings.Count -eq 0) "English script messages: $($file.Name)"
    }
    $env:AZD_CONTAINER_RUNTIME = ''
    Assert-True ((Resolve-ContainerEngine '') -eq 'docker') 'default engine'
    Assert-True ((Resolve-ContainerEngine 'podman') -eq 'podman') 'explicit podman'
    $env:AZD_CONTAINER_RUNTIME = 'podman'
    Assert-True ((Resolve-ContainerEngine '') -eq 'podman') 'configured engine'
    Assert-Throws { Resolve-ContainerEngine docker } 'engine conflict'
    Assert-Throws { Resolve-ContainerEngine nerdctl } 'unsupported engine'
    Assert-True (Test-MinimumVersion 'azd version 1.37.3 (commit abc)' '1.37.3') 'azd minimum'
    Assert-True (-not (Test-MinimumVersion '1.37.2' '1.37.3')) 'old azd'
    Assert-True (-not (Test-MinimumVersion '22.0.0-rc.1' '22.0.0')) 'preview rejected'

    $script:Calls = [Collections.Generic.List[string]]::new()
    $script:Stopped = $false
    $script:MachineFails = $false
    function Invoke-ToolProbe {
        param([string]$Name, [string[]]$Arguments)
        $script:Calls.Add("$Name $($Arguments -join ' ')")
        $text = ''; $code = 0
        if ($Arguments[0] -eq '--version') { $text = "$Name version 5.4.0" }
        elseif ($Arguments[0] -eq 'info') {
            if ($script:Stopped) { $code = 1 } else { $text = 'linux' }
        }
        elseif ($Arguments[0] -eq 'build') { $text = '--platform' }
        elseif ($Arguments[0] -eq 'buildx') { $code = 127 }
        elseif ($Arguments[0] -eq 'machine') {
            if ($script:MachineFails) { $code = 1 } else { $text = 'fixture-machine' }
        }
        return [pscustomobject]@{ Code = $code; Text = $text }
    }
    New-Results
    Test-ContainerRuntime podman
    Assert-True (-not (Has-Failure 'container-cli')) 'podman CLI'
    Assert-True (-not (Has-Failure 'builder')) 'podman native builder'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'container-engine' -and $_.Message -like '*does not verify where the engine is installed*' }).Count -eq 1) 'engine location is not inferred'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'container-workload' -and $_.Status -eq 'MANUAL' -and $_.Message -like '*do not guarantee that the actual workload will succeed*' }).Count -eq 1) 'actual container workload remains manual'
    Assert-True (@($script:Calls | Where-Object { $_ -like 'docker *' }).Count -eq 0) 'podman never probes docker'
    if ($IsWindows -or $IsMacOS) {
        Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'podman-machine' -and $_.Status -eq 'PASS' -and $_.Message -like '*fixture-machine*' }).Count -eq 1) 'podman machine list shown'
        $script:MachineFails = $true
        New-Results
        Test-ContainerRuntime podman
        Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'podman-machine' -and $_.Status -eq 'WARN' }).Count -eq 1) 'podman machine lookup failure warns'
        Assert-True (-not (Has-Failure 'container-engine')) 'machine lookup failure does not invalidate working engine'
    }
    $script:Stopped = $true
    $script:Calls.Clear()
    New-Results
    Test-ContainerRuntime docker
    Assert-True (Has-Failure 'container-engine') 'stopped engine fails'
    Assert-True (@($script:Calls | Where-Object { $_ -like 'podman *' }).Count -eq 0) 'no fallback'
    Remove-Item Function:\Invoke-ToolProbe
    . (Join-Path $root 'scripts\check-prerequisites.ps1')

    $script:SignedIn = $true
    $script:MissingNode = $false
    $script:Registered = $true
    function Invoke-ToolProbe {
        param([string]$Name, [string[]]$Arguments)
        $code = 0; $text = ''
        switch ($Name) {
            git { $text = 'git version 2.50.0' }
            node { $text = 'v22.1.0'; if ($script:MissingNode) { $code=127; $text='' } }
            modernize { $text = '1.0.95'; if ($script:ModernizeFailure) { $code=1 } }
            gh {
                if ($Arguments[0] -eq '--version') { $text = 'gh version 2.45.0'; if ($script:OldGh) { $text='gh version 2.44.0' } }
                elseif ($script:GhAuthFailure) { $code=1 }
            }
            az {
                switch ($Arguments[0]) {
                    version { $text='{}' }
                    extension { $text='1.3.0' }
                    account {
                        if (-not $script:SignedIn) { $code=1 }
                        elseif ($Arguments -contains 'state') { $text='Enabled' }
                        elseif ($script:IdentityFails) { $code=1 }
                        elseif ($script:MalformedIdentity) { $text='malformed subscription' }
                        elseif ($Arguments -contains 'tenantId') { $text='11111111-2222-3333-4444-555555555555' }
                        elseif ($Arguments -contains '[[id,name]]') { $text="subscription-id`tSubscription name" }
                        else { $code=1 }
                    }
                    cloud { $text='https://management.example.invalid/' }
                    rest { if ($script:TenantFails) { $code=1 } else { $text='Example tenant' } }
                    provider { $text=if ($script:Registered) { 'Registered' } else { 'NotRegistered' } }
                }
            }
            azd {
                if ($Arguments[0] -eq 'version') { $text='azd version 1.37.3' }
                elseif (-not $script:SignedIn) { $code=1 }
            }
            docker {
                switch ($Arguments[0]) {
                    --version { $text='Docker version 29.0.0' }
                    info { $text='linux' }
                    build { $text='--platform' }
                    buildx { $text='v0.20.0' }
                }
            }
            default { $code=127 }
        }
        return [pscustomobject]@{ Code=$code; Text=$text }
    }
    New-Results
    Test-CommonTools docker dotnet
    Assert-True (@($script:CheckResults | Where-Object Status -EQ FAIL).Count -eq 0) 'complete common tool fixture'
    & {
        $script:ModernizeFailure=$true; $script:OldGh=$true
        New-Results
        Test-CommonTools docker dotnet
        Assert-True (Has-Failure modernize) 'unusable Modernize fails'
        Assert-True (Has-Failure gh) 'old gh fails'
        $script:ModernizeFailure=$false; $script:OldGh=$false; $script:GhAuthFailure=$true
        New-Results
        Test-CommonTools docker dotnet
        Assert-True (Has-Failure gh-login) 'gh auth failure'
        $script:GhAuthFailure=$false
    }
    New-Results
    Test-CommonTools docker dotnet
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Status -eq 'MANUAL' -and $_.Message -like '*subscription-id*' }).Count -eq 1) 'subscription identity requires confirmation'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Message -ceq 'Subscription name (subscription-id)' }).Count -eq 1) 'subscription format'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Message -notlike '*11111111-2222-3333-4444-555555555555*' -and $_.Message -like '*Subscription name*' }).Count -eq 1) 'subscription excludes tenant ID'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-tenant' -and $_.Status -eq 'MANUAL' -and $_.Message -ceq 'Example tenant (11111111-2222-3333-4444-555555555555)' }).Count -eq 1) 'tenant name and ID require confirmation'
    $script:TenantFails=$true
    New-Results
    Test-CommonTools docker dotnet
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-tenant' -and $_.Status -eq 'WARN' -and $_.Message -like '*11111111-2222-3333-4444-555555555555*' }).Count -eq 1) 'tenant lookup failure warns and retains ID'
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Status -eq 'MANUAL' }).Count -eq 1) 'subscription preserved when tenant lookup fails'
    $script:TenantFails=$false
    $script:IdentityFails=$true
    New-Results
    Test-CommonTools docker dotnet
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Status -eq 'WARN' }).Count -eq 1) 'identity lookup failure warns'
    $script:IdentityFails=$false
    $script:MalformedIdentity=$true
    New-Results
    Show-AzureIdentity
    Assert-True (@($script:CheckResults | Where-Object { $_.Id -eq 'azure-subscription' -and $_.Status -eq 'WARN' }).Count -eq 1) 'malformed subscription warns'
    $script:MalformedIdentity=$false
    $script:SignedIn=$false; $script:MissingNode=$true
    New-Results
    Test-CommonTools docker dotnet
    Assert-True (Has-Failure node) 'missing Node fails'
    Assert-True (Has-Failure az-login) 'Azure CLI auth failure'
    Assert-True (Has-Failure azd-login) 'azd auth failure'
    $script:SignedIn=$true; $script:Registered=$false
    New-Results
    Test-CommonTools docker java
    Assert-True (Has-Failure 'Microsoft.DBforPostgreSQL') 'Java provider registration required'
    Remove-Item Function:\Invoke-ToolProbe
    . (Join-Path $root 'scripts\check-prerequisites.ps1')

    if ($IsWindows) {
        & {
            $Track='java'; $ContainerEngine='docker'; $Help=$false
            $env:AZD_CONTAINER_RUNTIME='docker'
            $script:NativeMissing=$false
            function Test-CommonTools {
                param($Engine, $SelectedTrack)
                Assert-True ($Engine -eq 'docker' -and $SelectedTrack -eq 'java') 'native Java runs common tools'
                Assert-True ($env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL -eq 'no') 'native Java disables dynamic installs'
                if ($script:NativeMissing) { Add-Check FAIL node 'fixture missing Node' }
            }
            function Test-JavaTools { Add-Check PASS jdk-8 'fixture'; Add-Check PASS jdk-25 'fixture' }
            function Test-DotnetTools { throw 'Java must not probe .NET tools' }
            $previous = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
            Assert-True ((Invoke-PrerequisiteMain) -eq 0) 'native Windows Java passes'
            Assert-True ($env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL -ceq $previous) 'dynamic-install state restored'
            Assert-True (@($script:CheckResults | Where-Object Id -eq 'jdk-25').Count -eq 1) 'native JDK check reached'
            $script:NativeMissing=$true
            Assert-True ((Invoke-PrerequisiteMain) -eq 1) 'native Java common failure propagated'
        }
        & {
            $Track='java'; $Help=$false
            $originalRuntime = $env:AZD_CONTAINER_RUNTIME
            $messages = [Collections.Generic.List[string]]::new()
            function Write-Host { param([string]$Object); $messages.Add($Object) }
            function Test-CommonTools {}
            function Test-JavaTools {}
            foreach ($case in @(
                @{ Engine=''; Configured=''; Remind=$false },
                @{ Engine='docker'; Configured='docker'; Remind=$false },
                @{ Engine='podman'; Configured=''; Remind=$true },
                @{ Engine=''; Configured='podman'; Remind=$false }
            )) {
                $ContainerEngine = $case.Engine
                $env:AZD_CONTAINER_RUNTIME = $case.Configured
                $messages.Clear()
                Assert-True ((Invoke-PrerequisiteMain) -eq 0) 'runtime reminder preserves successful checks'
                $reminders = @($messages | Where-Object { $_ -like '*AZD_CONTAINER_RUNTIME*' })
                Assert-True ($reminders.Count -eq [int]$case.Remind) "runtime reminder: engine=$ContainerEngine configured=$($case.Configured)"
                if ($case.Remind) {
                    Assert-True ($reminders[0] -ceq 'Before running azd in this shell, set $env:AZD_CONTAINER_RUNTIME = ''podman''.') 'Podman reminder uses PowerShell syntax'
                }
                Assert-True ($env:AZD_CONTAINER_RUNTIME -ceq $case.Configured) 'runtime reminder does not change the caller environment'
            }
            $env:AZD_CONTAINER_RUNTIME = $originalRuntime
        }
        . (Join-Path $root 'scripts\check-prerequisites.ps1')
        $env:ProgramFiles = Join-Path $temporary 'program-files'
        ${env:ProgramFiles(x86)} = Join-Path $temporary 'program-files-x86'
        $references = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
        [IO.Directory]::CreateDirectory((Join-Path $references 'RedistList')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $env:ProgramFiles 'IIS Express')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $env:ProgramFiles 'IIS Express\AppServer')) | Out-Null
        Set-Content (Join-Path $references 'mscorlib.dll') 'fixture'
        Set-Content (Join-Path $references 'RedistList\FrameworkList.xml') 'fixture'
        Set-Content (Join-Path $env:ProgramFiles 'IIS Express\iisexpress.exe') 'fixture'
        Set-Content (Join-Path $env:ProgramFiles 'IIS Express\AppServer\applicationhost.config') 'fixture'
        $vsRoot = Join-Path $temporary 'VS IDE'
        $msbuildPath = Join-Path $vsRoot 'MSBuild\Current\Bin\MSBuild.exe'
        $webTarget = Join-Path $vsRoot 'MSBuild\Microsoft\VisualStudio\v18.0\WebApplications\Microsoft.WebApplication.targets'
        foreach ($file in @($msbuildPath, $webTarget)) {
            [IO.Directory]::CreateDirectory((Split-Path $file -Parent)) | Out-Null
            Set-Content $file 'fixture'
        }
        $script:FakeRelease = 528040
        $script:FakeSdk = '10.0.100 [fixture]'
        $script:FakeFeature = 1
        $script:FakeVs = @(@{ installationVersion='18.0.1'; installationPath=$vsRoot }) | ConvertTo-Json -AsArray
        function Invoke-FrameworkProbe {
            param($File, $Arguments)
            Assert-True ($Arguments -contains '*') 'vswhere includes Build Tools products'
            return [pscustomobject]@{ Code=0; Text=$script:FakeVs }
        }
        function Get-CimInstance { [CmdletBinding()]param($ClassName, $Filter); return [pscustomobject]@{ InstallState=$script:FakeFeature } }
        function Get-Service { [CmdletBinding()]param($Name); return [pscustomobject]@{ Status='Running' } }
        function Get-ItemPropertyValue { [CmdletBinding()]param($LiteralPath, $Name); return $script:FakeRelease }
        function Get-Command { [CmdletBinding()]param($Name, $CommandType); return [pscustomobject]@{ Source='fixture-sqllocaldb' } }
        function Invoke-ToolProbe {
            param([string]$Name, [string[]]$Arguments)
            $text = if ($Name -like '*vswhere.exe') { $script:FakeVs } elseif ($Name -eq 'dotnet') { $script:FakeSdk } else { '16.0' }
            return [pscustomobject]@{ Code=0; Text=$text }
        }
        New-Results
        Test-DotnetTools
        Assert-True (-not (Has-Failure framework-runtime)) 'runtime 4.8 accepted'
        Assert-True (-not (Has-Failure framework-targeting)) 'targeting pack accepted'
        Assert-True (-not (Has-Failure framework-build)) 'VS IDE web build fixture'
        $buildToolsRoot = Join-Path $temporary 'Standalone Build Tools'
        Move-Item $vsRoot $buildToolsRoot
        $script:FakeVs = @(@{ installationVersion='17.14.1'; installationPath=$buildToolsRoot }) | ConvertTo-Json -AsArray
        $v18 = Join-Path $buildToolsRoot 'MSBuild\Microsoft\VisualStudio\v18.0'
        Rename-Item $v18 'v17.0'
        New-Results
        Test-DotnetTools
        Assert-True (-not (Has-Failure framework-build)) 'standalone Build Tools accepted without IDE'
        $webTarget = Join-Path $buildToolsRoot 'MSBuild\Microsoft\VisualStudio\v17.0\WebApplications\Microsoft.WebApplication.targets'
        Remove-Item $webTarget
        New-Results
        Test-DotnetTools
        Assert-True (Has-Failure framework-build) 'MSBuild alone without web targets rejected'
        Set-Content $webTarget 'fixture'
        $buildToolsMsbuild = Join-Path $buildToolsRoot 'MSBuild\Current\Bin\MSBuild.exe'
        Remove-Item $buildToolsMsbuild
        New-Results
        Test-DotnetTools
        Assert-True (Has-Failure framework-build) 'web targets without MSBuild rejected'
        Set-Content $buildToolsMsbuild 'fixture'
        $script:FakeVs = 'not-json'
        New-Results
        Test-DotnetTools
        Assert-True (Has-Failure framework-build) 'malformed vswhere output fails closed'
        $script:FakeVs = @(@{ installationVersion='17.14.1'; installationPath=$buildToolsRoot }) | ConvertTo-Json -AsArray
        Remove-Item (Join-Path $env:ProgramFiles 'IIS Express\AppServer\applicationhost.config')
        New-Results
        Test-DotnetTools
        Assert-True (Has-Failure iis-express) 'IIS exe alone without configuration template rejected'
        Set-Content (Join-Path $env:ProgramFiles 'IIS Express\AppServer\applicationhost.config') 'fixture'
        Assert-True (-not (Has-Failure dotnet-sdk)) '.NET 10 SDK accepted'
        Remove-Item (Join-Path $references 'mscorlib.dll')
        New-Results
        Test-DotnetTools
        Assert-True (-not (Has-Failure framework-runtime)) 'runtime independent of targeting pack'
        Assert-True (Has-Failure framework-targeting) 'runtime alone insufficient'
        $script:FakeRelease = 461808
        $script:FakeSdk = '10.0.100-preview.1 [fixture]'
        $script:FakeFeature = 2
        $script:FakeVs = '[]'
        New-Results
        Test-DotnetTools
        Assert-True (Has-Failure framework-runtime) 'old framework rejected'
        Assert-True (Has-Failure dotnet-sdk) 'preview SDK rejected'
        Assert-True (Has-Failure msmq-feature) 'disabled MSMQ rejected'
        Assert-True (Has-Failure framework-build) 'no qualifying build tools rejected'
        foreach ($name in @('Get-CimInstance','Get-Service','Get-ItemPropertyValue','Get-Command','Invoke-ToolProbe','Invoke-FrameworkProbe')) { Remove-Item "Function:\$name" }
        . (Join-Path $root 'scripts\check-prerequisites.ps1')
        $env:ProgramFiles = $savedProgramFiles
        ${env:ProgramFiles(x86)} = $savedProgramFilesX86
    }

    $destination = Join-Path $temporary 'destination with spaces'
    Assert-True ((Assert-SafeDestination $destination $root) -eq $destination) 'space destination'
    Push-Location $temporary
    try { Assert-True ((Assert-SafeDestination 'relative-child' $root) -eq (Join-Path $temporary 'relative-child')) 'relative path follows PowerShell location' }
    finally { Pop-Location }
    Assert-Throws { Assert-SafeDestination $root $root } 'workshop root rejected'
    Assert-Throws { Assert-SafeDestination (Join-Path $root 'docs\child') $root } 'documentation rejected'
    if ($IsWindows) { Assert-Throws { Assert-SafeDestination (Join-Path $root 'docs.\child') $root } 'Windows path alias rejected' }
    if ($IsWindows) { Assert-Throws { Assert-SafeDestination ('\\?\' + (Join-Path $root 'docs\child')) $root } 'extended device path rejected' }
    Assert-Throws { Assert-SafeDestination $HOME $root } 'home rejected'
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    Set-Content (Join-Path $destination '.hidden') 'preserve'
    Assert-Throws { Assert-SafeDestination $destination $root } 'hidden file prevents overwrite'
    Assert-True ((Get-Content (Join-Path $destination '.hidden') -Raw).Trim() -eq 'preserve') 'existing content preserved'
    if ($IsWindows) {
        $junction = Join-Path $temporary 'junction'
        New-Item -ItemType Junction -Path $junction -Target $destination | Out-Null
        Assert-Throws { Assert-SafeDestination (Join-Path $junction 'child') $root } 'junction rejected'
        Remove-Item -LiteralPath $junction
    }

    $fixture = Join-Path $temporary 'upstream'
    $app = Join-Path $fixture 'ContosoUniversity'
    [IO.Directory]::CreateDirectory($app) | Out-Null
    foreach ($name in @('ContosoUniversity.sln', 'ContosoUniversity.csproj', 'packages.config', '.gitignore')) {
        Set-Content -LiteralPath (Join-Path $app $name) -Value "fixture $name"
    }
    Set-Content -LiteralPath (Join-Path $fixture 'LICENSE') 'Fixture license, not a real sample license'
    Set-Content -LiteralPath (Join-Path $fixture 'NOTICE.md') 'Fixture notice'
    Set-Content -LiteralPath (Join-Path $fixture 'license-MIT.txt') 'Fixture alternate license'
    Set-Content -LiteralPath (Join-Path $fixture 'COPYRIGHT') 'Fixture copyright'
    Set-Content -LiteralPath (Join-Path $app 'ContosoUniversity.csproj') '<Project><PropertyGroup><TargetFrameworkVersion>v4.8</TargetFrameworkVersion></PropertyGroup></Project>'
    & git init --quiet $fixture
    & git -C $fixture config core.autocrlf false
    & git -C $fixture add .
    & git -C $fixture -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m "Fixture`n`nCo-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
    if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed' }
    $commit = (& git -C $fixture rev-parse HEAD).Trim()
    $definition = [pscustomobject]@{ Repository=$fixture; Commit=$commit; Subdirectory='ContosoUniversity'; Required=@('ContosoUniversity.sln','ContosoUniversity.csproj','packages.config') }
    $download = Join-Path $temporary 'download with spaces'
    Invoke-SampleDownload $download $definition $root
    Assert-True (Test-Path (Join-Path $download 'ContosoUniversity.sln')) 'flattened solution'
    Assert-True (Test-Path (Join-Path $download '.gitignore')) 'hidden files preserved'
    $workshopIgnore = Get-Content (Join-Path $root '.gitignore') -Raw
    Assert-True ($workshopIgnore -notmatch '(?m)^/(java|dotnet)/$') 'workshop tracks downloaded app directories'
    Assert-True (Test-Path (Join-Path $download 'UPSTREAM-LICENSE')) 'license preserved'
    $metadata = Get-Content (Join-Path $download 'upstream-source.json') -Raw | ConvertFrom-Json
    Assert-True ($metadata.commit -eq $commit) 'pinned provenance'
    Assert-True ($metadata.repository -eq $fixture -and $metadata.subdirectory -eq 'ContosoUniversity') 'repository and subdirectory provenance'
    Assert-True $metadata.licenseFileFound 'license metadata'
    foreach ($name in @('LICENSE', 'NOTICE.md', 'license-MIT.txt', 'COPYRIGHT')) {
        Assert-True ((Get-FileHash (Join-Path $fixture $name)).Hash -eq (Get-FileHash (Join-Path $download "UPSTREAM-$name")).Hash) "notice bytes preserved: $name"
    }
    foreach ($file in Get-ChildItem -LiteralPath $app -Force -File) {
        Assert-True ((Get-FileHash $file.FullName).Hash -eq (Get-FileHash (Join-Path $download $file.Name)).Hash) "source bytes unchanged: $($file.Name)"
    }
    Assert-True (-not (Test-Path (Join-Path $download '.git'))) 'download has no nested Git repository'
    $gitRoot = (& git -C $download rev-parse --show-toplevel).Trim()
    Assert-True ([IO.Path]::GetFullPath($gitRoot) -eq $root) 'download uses workshop Git root'
    Assert-Throws { Invoke-SampleDownload $download $definition $root } 'repeat refuses overwrite'
    $emptyTarget = Join-Path $temporary 'empty'
    [IO.Directory]::CreateDirectory($emptyTarget) | Out-Null
    Invoke-SampleDownload $emptyTarget $definition $root
    Assert-True (Test-Path (Join-Path $emptyTarget 'ContosoUniversity.sln')) 'existing empty destination'
    foreach ($collisionName in @('upstream-source.json', 'UPSTREAM-NOTICE.md')) {
        Set-Content -LiteralPath (Join-Path $app $collisionName) 'preserve upstream content'
        & git -C $fixture add .
        & git -C $fixture -c user.name=Fixture -c user.email=fixture@example.invalid commit --quiet -m "Fixture collision`n`nCo-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
        $definition.Commit = (& git -C $fixture rev-parse HEAD).Trim()
        $collisionTarget = Join-Path $temporary $collisionName
        Assert-Throws { Invoke-SampleDownload $collisionTarget $definition $root } "reject source collision: $collisionName"
        Assert-True (-not (Test-Path $collisionTarget)) "collision not published: $collisionName"
        Remove-Item -LiteralPath (Join-Path $app $collisionName)
    }
    $definition.Commit = '0000000000000000000000000000000000000000'
    $failed = Join-Path $temporary 'failed'
    Assert-Throws { Invoke-SampleDownload $failed $definition $root } 'bad commit fails'
    Assert-True (-not (Test-Path $failed)) 'failed download is not published'
    Assert-True (@(Get-ChildItem $temporary -Force | Where-Object Name -Like '.workshop-download-*').Count -eq 0) 'temporary paths cleaned'

    foreach ($trackName in @('java','dotnet')) {
        $sample = Get-SampleDefinition $trackName
        $bash = Get-Content (Join-Path $root 'scripts\download-sample.sh') -Raw
        Assert-True ($bash.Contains($sample.Commit)) "same commit in both shells: $trackName"
        Assert-True ($bash.Contains($sample.Repository)) "same source in both shells: $trackName"
    }
    if ($IsWindows) {
        & {
            $savedDownloadScripts = $script:DownloadScripts
            $preflightScripts = Join-Path $temporary 'preflight scripts'
            [IO.Directory]::CreateDirectory($preflightScripts) | Out-Null
            $preflightPath = Join-Path $preflightScripts 'check-prerequisites.ps1'
            [IO.File]::WriteAllText($preflightPath, @"
param([string]`$Track, [string]`$ContainerEngine, [switch]`$Help)
function Resolve-ContainerEngine {
${function:Resolve-ContainerEngine}
}
"@, [Text.UTF8Encoding]::new($true))
            $preflightCode = 1
            $preflightCalls = [Collections.Generic.List[string]]::new()
            $downloadCalls = [Collections.Generic.List[string]]::new()
            $Track='dotnet'; $Destination=Join-Path $temporary 'blocked-by-preflight'; $ContainerEngine='docker'; $Help=$false
            $env:AZD_CONTAINER_RUNTIME='docker'
            function Invoke-WorkshopPowerShell {
                param($ScriptPath, $BoundParameters, $RemainingArguments)
                $preflightCalls.Add($ScriptPath)
                Assert-True ($ScriptPath -eq $preflightPath) 'download preflight uses the shared console-preserving launcher'
                Assert-True ($BoundParameters.Track -eq $Track) 'preflight receives the selected track'
                Assert-True ($BoundParameters.ContainerEngine -eq $ContainerEngine) 'preflight receives the selected engine'
                Assert-True ($RemainingArguments.Count -eq 0) 'preflight has no additional arguments'
                $global:LASTEXITCODE = if ($preflightCode -eq 0) { 1 } else { 0 }
                return $preflightCode
            }
            function Invoke-SampleDownload {
                param($Target,$Definition,$WorkshopRoot)
                $downloadCalls.Add($Target)
                Assert-True ($Definition.Subdirectory -eq 'asset-manager') 'Java download uses pinned Java definition'
                Assert-True ($Definition.Required -contains 'mvnw.cmd') 'Windows wrapper required'
                Assert-True ($Target -eq $Destination) 'Java native destination unchanged'
            }
            try {
                $script:DownloadScripts = $preflightScripts
                Assert-True ((Invoke-DownloadMain) -eq 1) 'download propagates prerequisite failure rather than stale LASTEXITCODE'
                Assert-True ($downloadCalls.Count -eq 0 -and -not (Test-Path $Destination)) 'prerequisite failure prevents download'
                $Track='java'; $Destination=Join-Path $temporary 'native-java'; $preflightCode=0
                Assert-True ((Invoke-DownloadMain) -eq 0) 'Java reaches native download after preflight rather than stale LASTEXITCODE'
                Assert-True ($preflightCalls.Count -eq 2 -and $downloadCalls.Count -eq 1) 'each download runs preflight once'
            }
            finally { $script:DownloadScripts = $savedDownloadScripts }
        }
    }
    $documents = @((Get-Item (Join-Path $root 'README.md'))) + @(Get-ChildItem (Join-Path $root 'docs') -Recurse -Filter '*.md')
    $workshopPages = @($documents | Where-Object { $_.DirectoryName -eq $root -or ($_.Directory.Name -in @('java', 'dotnet') -and ($_.Name -eq 'README.md' -or $_.Name -match '^0[0-8]-.*\.md$')) })
    Assert-True ($workshopPages.Count -eq 21) '21 workshop pages (root and 20 track pages)'
    foreach ($document in $documents) {
        $text = Get-Content $document.FullName -Raw
        Assert-True ($text -match '[가-힣]') "Korean text: $($document.Name)"
        Assert-True ($text -notmatch '[\u3040-\u30ff]') "no accidental Japanese: $($document.Name)"
        foreach ($match in [regex]::Matches($text, '\[[^\]]+\]\(([^)]+)\)')) {
            $link = $match.Groups[1].Value
            if ($link -match '^[a-z]+:|^#') { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $document.DirectoryName ($link.Split('#')[0] -replace '/', [IO.Path]::DirectorySeparatorChar)))
            Assert-True (Test-Path -LiteralPath $target -PathType Leaf) "local link: $link in $($document.Name)"
        }
        if ($document.DirectoryName -eq $root -or $document.FullName -notin $workshopPages.FullName) { continue }
        $track = $document.Directory.Name
        $trackLabel = if ($track -eq 'java') { 'Java' } else { '.NET' }
        $navigation = ($text -split '\r?\n' | Where-Object { $_ -match '^\[전체 목차\]' } | Select-Object -First 1)
        Assert-True (-not [string]::IsNullOrWhiteSpace($navigation)) "top navigation: $track/$($document.Name)"
        $expected = @('전체 목차')
        if ($document.Name -ne 'README.md') { $expected += "$trackLabel 목차" }
        if ($document.Name -match '^0[1-7]-') { $expected += '이전:' }
        if ($document.Name -notin @('07-cleanup.md', '08-troubleshooting.md')) { $expected += '다음:' }
        if ($document.Name -ne '08-troubleshooting.md') { $expected += '문제 해결' }
        $links = @([regex]::Matches($navigation, '\[([^\]]+)\]\(([^)]+)\)'))
        Assert-True ($links.Count -eq $expected.Count) "navigation count: $track/$($document.Name)"
        for ($i = 0; $i -lt $expected.Count; $i++) {
            $label = $links[$i].Groups[1].Value
            Assert-True ($label.StartsWith($expected[$i])) "navigation order $($expected[$i]): $track/$($document.Name)"
            $target = [IO.Path]::GetFullPath((Join-Path $document.DirectoryName $links[$i].Groups[2].Value))
            Assert-True ($target -ne $document.FullName) "no self navigation: $track/$($document.Name)"
        }
    }
    & (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $PSScriptRoot 'java-deployment.tests.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'Java deployment helper suite'
    Write-Host "PASS: $script:Passed PowerShell assertions"
}
finally {
    $env:AZD_CONTAINER_RUNTIME = $savedEngine
    $env:ProgramFiles = $savedProgramFiles
    ${env:ProgramFiles(x86)} = $savedProgramFilesX86
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
