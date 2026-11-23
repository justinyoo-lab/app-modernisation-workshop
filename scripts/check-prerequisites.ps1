[CmdletBinding()]
param(
    [string]$Track,
    [string]$ContainerEngine,
    [switch]$Help
)

. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

$script:WorkshopScripts = $PSScriptRoot
. (Join-Path $PSScriptRoot 'dotnet-framework-tools.ps1')
. (Join-Path $PSScriptRoot 'java-tools.ps1')

function Resolve-ContainerEngine {
    param([string]$Requested, [string]$Configured = $env:AZD_CONTAINER_RUNTIME)
    foreach ($value in @($Requested, $Configured)) {
        if ($value -and $value -cnotin @('docker', 'podman')) {
            throw [ArgumentException]::new('ContainerEngine/AZD_CONTAINER_RUNTIME must be docker or podman.')
        }
    }
    if ($Requested -and $Configured -and $Requested -cne $Configured) {
        throw [ArgumentException]::new('ContainerEngine and AZD_CONTAINER_RUNTIME differ. Set matching values in the current shell first.')
    }
    if ($Requested) { return $Requested }
    if ($Configured) { return $Configured }
    return 'docker'
}

function Invoke-ToolProbe {
    param([string]$Name, [string[]]$Arguments = @())
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return [pscustomobject]@{ Code = 127; Text = '' } }
    try {
        $text = (& $command.Source @Arguments 2>&1 | Out-String).Trim()
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
    }
    catch {
        return [pscustomobject]@{ Code = 126; Text = $_.Exception.Message }
    }
}

function Add-Check {
    param([string]$Status, [string]$Id, [string]$Message)
    $script:CheckResults.Add([pscustomobject]@{ Status = $Status; Id = $Id; Message = $Message })
    $context = if ($script:CheckContext) { $script:CheckContext } else { 'PowerShell' }
    Write-WorkshopMessage "[$Status] [$context] ${Id}: $Message"
}

function Test-AzureProvider {
    param([string]$Provider)
    $state = Invoke-ToolProbe az @('provider', 'show', '--namespace', $Provider, '--query', 'registrationState', '--output', 'tsv')
    if ($state.Code -eq 0 -and $state.Text -eq 'Registered') { Add-Check PASS $Provider 'Registered' }
    else { Add-Check FAIL $Provider "Could not verify registration (exit code $($state.Code)): $($state.Text). Register through the installer or resolve the query error." }
}

function Show-AzureIdentity {
    $identity = Invoke-ToolProbe az @('account', 'show', '--query', '[[id,name]]', '--output', 'tsv')
    if ($identity.Code -ne 0 -or -not $identity.Text) {
        Add-Check WARN 'azure-subscription' 'Could not query the current subscription. Manually verify the target subscription and tenant.'
        return
    }
    $subscription = $identity.Text -split "`t", 2
    if ($subscription.Count -ne 2 -or -not $subscription[0] -or -not $subscription[1]) {
        Add-Check WARN 'azure-subscription' 'Could not parse the current subscription ID and name. Manually verify the target subscription.'
        return
    }
    Add-Check MANUAL 'azure-subscription' "$($subscription[1]) ($($subscription[0]))"
    $tenant = Invoke-ToolProbe az @('account', 'show', '--query', 'tenantId', '--output', 'tsv')
    $tenantId = [guid]::Empty
    if ($tenant.Code -ne 0 -or -not [guid]::TryParse($tenant.Text, [ref]$tenantId)) {
        Add-Check WARN 'azure-tenant' 'Could not query the current tenant ID, so the tenant name cannot be verified.'
        return
    }
    $cloud = Invoke-ToolProbe az @('cloud', 'show', '--query', 'endpoints.resourceManager', '--output', 'tsv')
    if ($cloud.Code -ne 0 -or $cloud.Text -notmatch '^https://') {
        Add-Check WARN 'azure-tenant' "Tenant ID: $tenantId. Could not query the Azure cloud endpoint, so the tenant name cannot be verified."
        return
    }
    $url = $cloud.Text.TrimEnd('/') + '/tenants?api-version=2022-12-01'
    $name = Invoke-ToolProbe az @('rest', '--method', 'get', '--url', $url, '--query', "value[?tenantId=='$tenantId'].displayName | [0]", '--output', 'tsv', '--only-show-errors')
    if ($name.Code -eq 0 -and $name.Text -and $name.Text -notin @('None', 'null')) {
        Add-Check MANUAL 'azure-tenant' "$($name.Text) ($tenantId)"
    }
    else { Add-Check WARN 'azure-tenant' "Tenant ID: $tenantId. Could not query the tenant name. Check permissions, network access, and Azure Portal." }
}

function Test-MinimumVersion {
    param([string]$Text, [version]$Minimum)
    $match = [regex]::Match($Text, '(?<!\d)(\d+\.\d+\.\d+)(?![\d-])')
    return $match.Success -and ([version]$match.Groups[1].Value -ge $Minimum)
}

function Test-ContainerRuntime {
    param([string]$Engine)
    $version = Invoke-ToolProbe $Engine @('--version')
    if ($version.Code -ne 0) {
        Add-Check FAIL 'container-cli' "$Engine failed (exit code $($version.Code)). See the setup guide for your track."
        return
    }
    Add-Check PASS 'container-cli' "$Engine CLI output: $($version.Text)"
    $format = if ($Engine -eq 'docker') { '{{.OSType}}' } else { '{{.Host.OS}}' }
    $info = Invoke-ToolProbe $Engine @('info', '--format', $format)
    if ($info.Code -ne 0) {
        Add-Check FAIL 'container-engine' "Could not connect to $Engine. Check engine or Podman machine status and permissions. This script will not start the engine or switch to another one automatically."
    }
    elseif ($info.Text.Trim() -ne 'linux') {
        Add-Check FAIL 'container-engine' 'Could not verify a Linux environment for the selected engine.'
    }
    else { Add-Check PASS 'container-engine' "$Engine CLI connected to a Linux container engine. This check does not verify where the engine is installed." }
    if ($Engine -eq 'docker') {
        $builder = Invoke-ToolProbe docker @('build', '--help')
        if ($builder.Code -eq 0 -and $builder.Text -match '--platform') { Add-Check PASS 'builder-command' 'Found --platform in Docker CLI help. An actual build has not been verified.' }
        else { Add-Check FAIL 'builder-command' 'Could not verify Docker --platform build support.' }
        $buildx = Invoke-ToolProbe docker @('buildx', 'version')
        if ($buildx.Code -eq 0) { Add-Check PASS 'builder' 'Docker CLI returned the Buildx version. An actual build has not been verified.' }
        else { Add-Check WARN 'builder' 'Could not verify Buildx. Verify build support during the actual azd package step.' }
    }
    else {
        if ($IsWindows -or $IsMacOS) {
            $machines = Invoke-ToolProbe podman @('machine', 'list')
            if ($machines.Code -eq 0) { Add-Check PASS 'podman-machine' "Podman machine list (verify the selected connection separately): $($machines.Text)" }
            else { Add-Check WARN 'podman-machine' 'Could not list Podman machines. Manually check the machine and connection settings.' }
        }
        $builder = Invoke-ToolProbe podman @('build', '--help')
        if ($builder.Code -eq 0 -and $builder.Text -match '--platform') {
            Add-Check PASS 'builder' 'Found --platform in Podman CLI help. An actual build has not been verified. Docker Buildx is not required.'
        }
        else { Add-Check FAIL 'builder' 'Could not verify Podman --platform build support.' }
    }
    Add-Check MANUAL 'container-workload' 'During the workshop, verify an actual linux/amd64 image build, container port access, and publishing to ACR from this shell. The PASS results above do not guarantee that the actual workload will succeed.'
}

function Test-CommonTools {
    param([string]$Engine, [string]$SelectedTrack)
    $git = Invoke-ToolProbe git @('--version')
    if ($git.Code -eq 0) { Add-Check PASS git $git.Text }
    else { Add-Check FAIL git 'Install Git and check PATH.' }
    $node = Invoke-ToolProbe node @('--version')
    if ($node.Code -eq 0 -and (Test-MinimumVersion $node.Text '22.0.0')) { Add-Check PASS node $node.Text }
    else { Add-Check FAIL node 'A stable version of Node.js 22 or later is required.' }
    $modernize = Invoke-ToolProbe modernize @('--version')
    if ($modernize.Code -eq 0 -and $modernize.Text) { Add-Check PASS modernize $modernize.Text }
    else { Add-Check FAIL modernize 'Check the Modernize CLI installation and PATH.' }
    $gh = Invoke-ToolProbe gh @('--version')
    if ($gh.Code -eq 0 -and (Test-MinimumVersion $gh.Text '2.45.0')) {
        Add-Check PASS gh $gh.Text
        $auth = Invoke-ToolProbe gh @('auth', 'status')
        if ($auth.Code -eq 0) { Add-Check PASS 'gh-login' 'Verified GitHub CLI authentication. Copilot model access is separate.' }
        else { Add-Check FAIL 'gh-login' 'Run gh auth login manually or resolve the authentication error.' }
    }
    else { Add-Check FAIL gh 'GitHub CLI 2.45.0 or later is required.' }
    $az = Invoke-ToolProbe az @('version', '--output', 'json')
    if ($az.Code -eq 0) {
        Add-Check PASS az 'Azure CLI is available.'
        $extension = Invoke-ToolProbe az @('extension', 'show', '--name', 'containerapp', '--query', 'version', '--output', 'tsv')
        if ($extension.Code -eq 0 -and $extension.Text) { Add-Check PASS 'az-containerapp' "Extension version: $($extension.Text)" }
        else { Add-Check FAIL 'az-containerapp' 'Install the containerapp extension through the installer or resolve the query error.' }
        $account = Invoke-ToolProbe az @('account', 'show', '--query', 'state', '--output', 'tsv')
        if ($account.Code -eq 0 -and $account.Text -eq 'Enabled') {
            Add-Check PASS 'az-login' 'An enabled subscription is selected.'
            Show-AzureIdentity
            $providers = @('Microsoft.App', 'Microsoft.OperationalInsights', 'Microsoft.Storage', 'Microsoft.ContainerRegistry', 'Microsoft.ServiceBus')
            $providers += if ($SelectedTrack -eq 'java') { 'Microsoft.DBforPostgreSQL' } else { 'Microsoft.Sql' }
            foreach ($provider in $providers) {
                Test-AzureProvider $provider
            }
        }
        else { Add-Check FAIL 'az-login' 'Run az login and select an enabled subscription, or resolve the subscription query error.' }
    }
    else { Add-Check FAIL az 'Install Azure CLI or resolve the execution error.' }
    $azd = Invoke-ToolProbe azd @('version')
    if ($azd.Code -eq 0 -and (Test-MinimumVersion $azd.Text '1.37.3')) {
        Add-Check PASS azd $azd.Text
        $login = Invoke-ToolProbe azd @('auth', 'login', '--check-status')
        if ($login.Code -eq 0) { Add-Check PASS 'azd-login' 'Verified azd authentication.' }
        else { Add-Check FAIL 'azd-login' 'Run azd auth login manually or resolve the authentication error. This is separate from az authentication.' }
    }
    else { Add-Check FAIL azd 'This workshop requires azd 1.37.3 or later. This script will not update it automatically.' }
    Test-ContainerRuntime $Engine
    Add-Check MANUAL 'copilot-app' 'Check Copilot app sign-in, license, organization policies, and terminal access.'
    Add-Check MANUAL 'azure-access' 'Confirm that the Azure CLI subscription shown above is the workshop target. Check its regions, quotas, and permissions for role assignments and database Entra administrator configuration.'
}

function Test-DotnetTools {
    try {
        $feature = Get-CimInstance Win32_OptionalFeature -Filter "Name='MSMQ-Server'" -ErrorAction Stop
        if ($feature -and $feature.InstallState -eq 1) { Add-Check PASS msmq-feature 'The MSMQ Server feature is enabled.' }
        else { Add-Check FAIL msmq-feature 'Enable the MSMQ Server feature and complete any required restart.' }
    }
    catch { Add-Check FAIL msmq-feature "Could not query the MSMQ feature: $($_.Exception.Message)" }
    $service = Get-Service MSMQ -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') { Add-Check PASS msmq-service 'The MSMQ service is running.' }
    else { Add-Check FAIL msmq-service 'The MSMQ service is missing or not running.' }
    try {
        $tools = Get-DotnetFrameworkBuildTools
        $msbuild = Invoke-ToolProbe $tools.MSBuild @('-version', '-nologo')
        if ($msbuild.Code -ne 0) { throw 'Could not run MSBuild.exe.' }
        Add-Check PASS framework-build "Build tools available without launching the IDE: $($tools.MSBuild) / Web targets: $($tools.WebTools)"
    }
    catch { Add-Check FAIL framework-build $_.Exception.Message }
    try {
        $release = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop
        if ($release -ge 528040) { Add-Check PASS framework-runtime '.NET Framework runtime 4.8 or later is installed.' }
        else { Add-Check FAIL framework-runtime '.NET Framework runtime 4.8 or later is required.' }
    }
    catch { Add-Check FAIL framework-runtime "Could not query the runtime registry: $($_.Exception.Message)" }
    $references = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
    if ((Test-Path -LiteralPath (Join-Path $references 'mscorlib.dll')) -and (Test-Path -LiteralPath (Join-Path $references 'RedistList\FrameworkList.xml'))) {
        Add-Check PASS framework-targeting '.NET Framework 4.8 reference assemblies are installed.'
    }
    else { Add-Check FAIL framework-targeting 'The 4.8 Targeting Pack is required. Installing only the runtime is not sufficient.' }
    $sdks = Invoke-ToolProbe dotnet @('--list-sdks')
    if ($sdks.Code -eq 0 -and $sdks.Text -match '(?m)^10\.\d+\.\d+\s+\[') { Add-Check PASS dotnet-sdk 'A stable .NET 10 SDK is installed.' }
    else { Add-Check FAIL dotnet-sdk 'The .NET 10 SDK is required. A runtime-only installation does not pass this check.' }
    try {
        $iis = Get-WorkshopIisExpress
        Add-Check PASS iis-express "IIS Express executable and configuration template found: $($iis.Exe)"
    }
    catch { Add-Check FAIL iis-express $_.Exception.Message }
    $localdb = Get-Command SqlLocalDB -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $localdb) {
        $localdb = Get-ChildItem "$env:ProgramFiles\Microsoft SQL Server\*\Tools\Binn\SqlLocalDB.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if ($localdb) {
        $db = Invoke-ToolProbe $localdb @('versions')
        if ($db.Code -eq 0 -and $db.Text) { Add-Check PASS localdb 'Verified the SQL Server LocalDB installation.' }
        else { Add-Check FAIL localdb 'LocalDB failed to run. Check its installation and permissions.' }
    }
    else { Add-Check FAIL localdb 'Install SQL Server Express LocalDB.' }
}

function Test-JavaTools {
    foreach ($major in @(8, 25)) {
        $jdk = Find-WorkshopJava -Major $major
        if ($jdk) { Add-Check PASS "jdk-$major" "Verified Temurin java and javac: $($jdk.Home)" }
        else { Add-Check FAIL "jdk-$major" "A working Temurin JDK $major is required. See the installer and Java setup guide." }
    }
}

function Invoke-PrerequisiteMain {
    if ($Help) {
        Write-Host './scripts/check-prerequisites.ps1 -Track java|dotnet [-ContainerEngine docker|podman]'
        return 0
    }
    if ($Track -cnotin @('java', 'dotnet')) { Write-WorkshopMessage '[FAIL] Specify -Track java or -Track dotnet.'; return 2 }
    try { $engine = Resolve-ContainerEngine $ContainerEngine }
    catch [ArgumentException] { Write-WorkshopMessage "[FAIL] $($_.Exception.Message)"; return 2 }
    $script:CheckResults = [Collections.Generic.List[object]]::new()
    if (-not $IsWindows) { Write-WorkshopMessage '[FAIL] PowerShell entrypoints are Windows-only. For the Java track, run ./scripts/check-prerequisites.sh.'; return 1 }
    $script:CheckContext = 'Windows host'
    if ($PSVersionTable.PSVersion.Major -ge 7) { Add-Check PASS pwsh "PowerShell $($PSVersionTable.PSVersion)" }
    else { Add-Check FAIL pwsh 'PowerShell 7 is required.' }
    Write-Host "Track: $Track / Engine: $engine / Environment: Windows"
    $previous = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
    try {
        $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
        Test-CommonTools $engine $Track
        if ($Track -eq 'java') { Test-JavaTools } else { Test-DotnetTools }
    }
    finally { $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = $previous }
    $failures = @($script:CheckResults | Where-Object Status -eq 'FAIL').Count
    Write-Host "Required checks failed: $failures. MANUAL items have not been verified automatically."
    if ($engine -eq 'podman' -and $env:AZD_CONTAINER_RUNTIME -ne 'podman') {
        Write-Host 'Before running azd in this shell, set $env:AZD_CONTAINER_RUNTIME = ''podman''.'
    }
    if ($failures -gt 0) { return 1 }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-PrerequisiteMain) }
