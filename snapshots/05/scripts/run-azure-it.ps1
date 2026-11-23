param()

. (Join-Path $PSScriptRoot '../../scripts/powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

function Test-AzureItInteractive {
    return -not ($env:CI -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or
        @([Environment]::GetCommandLineArgs() | Where-Object { $_ -like '-NonI*' }).Count -gt 0)
}

function Get-AzureItAccountValue([string]$Query) {
    $value = & az account show --query $Query --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or @($value).Count -ne 1 -or "$value" -notmatch '^\S+$' -or "$value" -match '^<.*>$') {
        throw "Azure CLI account lookup failed or returned an invalid value: $Query"
    }
    return "$value"
}

function Get-AzureItAzdValue([string]$Name) {
    $value = & azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or @($value).Count -ne 1 -or "$value" -notmatch '^\S+$' -or "$value" -match '^<.*>$') {
        throw "azd lookup failed or returned an invalid value: $Name"
    }
    return "$value"
}

function Get-AzureItNamespace([string]$Value) {
    $name = $Value.ToLowerInvariant() -replace '\.servicebus\.windows\.net$', ''
    if ($name -notmatch '^[a-z0-9][a-z0-9-]{4,48}[a-z0-9]$') { throw 'Invalid Service Bus namespace.' }
    return "$name.servicebus.windows.net"
}

function Test-AzureItReport([string]$File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Missing test result: $File" }
    try { [xml]$result = Get-Content -LiteralPath $File -Raw -ErrorAction Stop }
    catch { throw "Invalid test result: $File" }
    if ($result.testsuite.tests -cne '1' -or $result.testsuite.failures -cne '0' -or
        $result.testsuite.errors -cne '0' -or $result.testsuite.skipped -cne '0') {
        throw "Test result is incomplete, skipped, or failed: $File"
    }
}

function Invoke-AzureItMaven([string]$Reports) {
    & './mvnw.cmd' '-Pazure-it' '-pl' 'web,worker' '-am' '-o' "-Dazure.it.report.dir=$Reports" 'verify' | Out-Host
    return $LASTEXITCODE
}

function Invoke-AzureIt {
    $names = @(
        'AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP', 'AZURE_IT_PG_HOST', 'AZURE_IT_PG_DATABASE',
        'AZURE_IT_BLOB_ENDPOINT', 'AZURE_IT_BLOB_CONTAINER', 'AZURE_IT_SERVICEBUS_NAMESPACE', 'AZURE_IT_SERVICEBUS_QUEUE',
        'AZURE_IT_APP_SERVICEBUS_NAMESPACE', 'AZURE_IT_APP_SERVICEBUS_QUEUE', 'AZURE_IT_PG_USER',
        'AZURE_IT_APPROVED', 'AZURE_EXTENSION_USE_DYNAMIC_INSTALL', 'AZURE_AUTO_UPGRADE_ENABLE', 'JAVA_HOME', 'PATH'
    )
    $original = @{}
    foreach ($name in $names) { $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $appDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
        if ((Get-Location).ProviderPath -ne $appDir -or -not (Test-Path './mvnw.cmd') -or -not (Test-Path './azure.yaml')) {
            throw 'Run this script from the app root.'
        }
        if (-not (Test-AzureItInteractive)) { throw 'Interactive approval is required; CI and redirected terminals are not allowed.' }
        if (-not (Get-Command az -ErrorAction SilentlyContinue) -or -not (Get-Command azd -ErrorAction SilentlyContinue)) {
            throw 'Azure CLI and azd are required; nothing was installed.'
        }
        if (-not (Select-String -Quiet -LiteralPath './pom.xml' -Pattern '<id>azure-it</id>') -or
            -not (Select-String -Quiet -LiteralPath './worker/pom.xml' -Pattern '<id>azure-it</id>')) {
            throw 'The azure-it Maven profile is missing.'
        }
        $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
        $env:AZURE_AUTO_UPGRADE_ENABLE = 'false'
        $type = Get-AzureItAccountValue 'user.type'
        $user = Get-AzureItAccountValue 'user.name'
        $subscription = Get-AzureItAccountValue 'id'
        if ($type -cne 'user') { throw 'Only an Azure CLI user account is supported.' }
        foreach ($name in $names[0..9]) {
            [Environment]::SetEnvironmentVariable($name, (Get-AzureItAzdValue $name), 'Process')
        }
        if ($subscription -ine $env:AZURE_SUBSCRIPTION_ID) { throw 'Azure CLI and azd subscriptions differ; no subscription was changed.' }
        $env:AZURE_IT_PG_USER = $user
        $testNamespace = Get-AzureItNamespace $env:AZURE_IT_SERVICEBUS_NAMESPACE
        $appNamespace = Get-AzureItNamespace $env:AZURE_IT_APP_SERVICEBUS_NAMESPACE
        if ($testNamespace -ieq $appNamespace -and $env:AZURE_IT_SERVICEBUS_QUEUE -ieq $env:AZURE_IT_APP_SERVICEBUS_QUEUE) {
            throw 'Test queue is the app queue.'
        }
        if ($env:AZURE_IT_PG_HOST -notmatch '^[a-z0-9][a-z0-9-]*\.postgres\.database\.azure\.com$' -or $env:AZURE_IT_PG_DATABASE -notmatch '^[A-Za-z0-9_-]+$' -or
            $env:AZURE_IT_BLOB_ENDPOINT -notmatch '^https://[a-z0-9]{3,24}\.blob\.core\.windows\.net/?$' -or
            $env:AZURE_IT_BLOB_CONTAINER -cnotmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$' -or
            $env:AZURE_IT_SERVICEBUS_QUEUE -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,259}$' -or
            $env:AZURE_IT_APP_SERVICEBUS_QUEUE -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,259}$') {
            throw 'Invalid target format; no test was run.'
        }
        Write-Host "User / PostgreSQL user: $user`nSubscription: $subscription`nResource group: $env:AZURE_RESOURCE_GROUP"
        Write-Host "PostgreSQL: $env:AZURE_IT_PG_HOST / $env:AZURE_IT_PG_DATABASE`nBlob: $env:AZURE_IT_BLOB_ENDPOINT / $env:AZURE_IT_BLOB_CONTAINER"
        Write-Host "Test queue: $testNamespace / $env:AZURE_IT_SERVICEBUS_QUEUE`nApp queue: $appNamespace / $env:AZURE_IT_APP_SERVICEBUS_QUEUE"
        Write-Host 'Writes: one new DB row, private test blobs and one message in a session-enabled test queue.'
        Write-Host 'Reads: the test row and blobs, container properties, and only the new message session.'
        Write-Host 'Test data is retained. Verify the DB user, access, network, costs and manual cleanup instructions.'
        if ((Read-Host 'Type RUN to approve these targets and changes') -cne 'RUN') { throw 'Cancelled; no tests were run.' }
        . (Join-Path $PSScriptRoot '../../scripts/use-java.ps1') -Jdk 25
        $base = Join-Path $appDir 'worker/target/azure-it-reports'
        $null = New-Item -ItemType Directory -Force -Path $base -ErrorAction Stop
        $root = Join-Path $base "run-$([guid]::NewGuid().ToString())"
        $null = New-Item -ItemType Directory -Path $root -ErrorAction Stop
        $reports = Join-Path $root 'reports'
        $env:AZURE_IT_APPROVED = 'YES'
        Write-Host "[INFO] New reports: $reports"
        if ((Invoke-AzureItMaven $reports) -ne 0) { throw 'Maven or Azure integration tests failed.' }
        foreach ($class in @('PostgresAzureIT', 'BlobAzureIT', 'ServiceBusAzureIT')) {
            Test-AzureItReport (Join-Path $reports "TEST-com.microsoft.migration.assets.worker.azureit.$class.xml")
        }
        Write-Host '[PASS] PostgreSQL, Blob and Service Bus Azure integration tests succeeded.'
        return 0
    }
    catch {
        Write-Host "[FAIL] $($_.Exception.Message)"
        return 1
    }
    finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
    }
}

if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-AzureIt) }
