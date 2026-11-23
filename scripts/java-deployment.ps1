. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

function Write-JavaDeploymentMessage {
    param([string]$Status, [string]$Message)
    [Console]::Error.WriteLine("[$Status] $Message")
}

function Invoke-JavaDeploymentTool {
    param([string]$Name, [string[]]$Arguments)
    $output = & $Name @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit code $LASTEXITCODE)." }
    return $output
}

function Get-JavaDeploymentValue {
    param([string]$Name)
    $value = Invoke-JavaDeploymentTool azd @('env', 'get-value', $Name)
    if (-not $value -or @($value).Count -ne 1 -or "$value" -match '[\r\n]') {
        throw "Missing or multiline azd value: $Name"
    }
    return "$value"
}

function Get-JavaDeploymentContext {
    if (-not (Test-Path -LiteralPath 'azure.yaml' -PathType Leaf)) {
        throw 'Run this helper from the application root containing azure.yaml.'
    }
    $context = @{
        Subscription = Get-JavaDeploymentValue AZURE_SUBSCRIPTION_ID
        Group = Get-JavaDeploymentValue AZURE_RESOURCE_GROUP
    }
    $null = Invoke-JavaDeploymentTool az @('account', 'show', '--subscription', $context.Subscription, '--query', 'id', '--output', 'tsv')
    Write-JavaDeploymentMessage INFO "Subscription: $($context.Subscription) / Resource group: $($context.Group)"
    return $context
}

function Test-JavaDeploymentInteractive {
    return Test-WorkshopBootstrapInteractive
}

function Confirm-JavaDeploymentChange {
    param([string]$Message)
    if (-not (Test-JavaDeploymentInteractive)) {
        throw 'Changes require an interactive terminal; CI/noninteractive execution is not allowed.'
    }
    Write-JavaDeploymentMessage WARN $Message
    if ((Read-Host 'Type APPLY to continue') -cne 'APPLY') { throw 'Cancelled; no change was requested.' }
}

function Get-JavaDeploymentIdentity {
    param($Context, [string]$App)
    $json = Invoke-JavaDeploymentTool az @('containerapp', 'show', '--subscription', $Context.Subscription,
        '--resource-group', $Context.Group, '--name', $App, '--query', 'identity.userAssignedIdentities', '--output', 'json')
    $identities = $json | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if (-not $identities -or $identities.Count -ne 1) { throw "$App must have exactly one user-assigned identity." }
    $id = @($identities.Keys)[0]
    $name = Invoke-JavaDeploymentTool az @('identity', 'show', '--ids', $id, '--query', 'name', '--output', 'tsv')
    if (-not $name -or @($name).Count -ne 1) { throw "$App returned no single identity name." }
    return "$name"
}

function Get-JavaDatabaseInfo {
    param($Context)
    $Context.Server = Get-JavaDeploymentValue POSTGRESQL_SERVER
    $Context.Database = Get-JavaDeploymentValue POSTGRESQL_DATABASE
    $Context.Admin = Get-JavaDeploymentValue POSTGRESQL_ADMIN_NAME
    $Context.HostName = Invoke-JavaDeploymentTool az @('postgres', 'flexible-server', 'show', '--subscription', $Context.Subscription,
        '--resource-group', $Context.Group, '--name', $Context.Server, '--query', 'fullyQualifiedDomainName', '--output', 'tsv')
    if (@($Context.HostName).Count -ne 1 -or "$($Context.HostName)" -notmatch '^[A-Za-z0-9.-]+$') {
        throw 'Invalid PostgreSQL FQDN.'
    }
    $Context.Web = Get-JavaDeploymentIdentity $Context (Get-JavaDeploymentValue WEB_CONTAINER_APP_NAME)
    $Context.Worker = Get-JavaDeploymentIdentity $Context (Get-JavaDeploymentValue WORKER_CONTAINER_APP_NAME)
    return $Context
}

function Show-JavaDatabaseInfo {
    param($Context)
    [pscustomobject][ordered]@{
        Server = $Context.Server; Host = $Context.HostName; Administrator = $Context.Admin
        Web = $Context.Web; Worker = $Context.Worker; Database = $Context.Database
    } | Format-List | Out-Host
}

function New-JavaDatabaseCertificate {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('workshop-postgres-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $complete = $false
    try {
        Write-JavaDeploymentMessage INFO 'Downloading Azure PostgreSQL root CAs from DigiCert and Microsoft.'
        $pem = foreach ($url in @(
            'https://cacerts.digicert.com/DigiCertGlobalRootG2.crt',
            'https://www.microsoft.com/pkiops/certs/Microsoft%20RSA%20Root%20Certificate%20Authority%202017.crt'
        )) {
            $response = Invoke-WebRequest -Uri $url -TimeoutSec 30 -ErrorAction Stop
            $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$response.Content)
            try {
                $base64 = [Convert]::ToBase64String($certificate.RawData, [Base64FormattingOptions]::InsertLineBreaks)
                "-----BEGIN CERTIFICATE-----`n$base64`n-----END CERTIFICATE-----"
            }
            finally { $certificate.Dispose() }
        }
        $path = Join-Path $directory 'roots.pem'
        Set-Content -LiteralPath $path -Value $pem -Encoding ascii -ErrorAction Stop
        $complete = $true
        return $path
    }
    finally {
        if (-not $complete) { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction Stop }
    }
}

function Register-JavaDatabaseClientIp {
    param([string]$ClientIp)
    $parsed = $null
    if ($ClientIp -notmatch '^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$' -or
        -not [Net.IPAddress]::TryParse($ClientIp, [ref]$parsed) -or
        $ClientIp -in @('0.0.0.0', '255.255.255.255')) {
        throw 'Supply one unambiguous IPv4 address, not an all-Azure or all-internet address.'
    }
    $context = Get-JavaDeploymentContext
    $server = Get-JavaDeploymentValue POSTGRESQL_SERVER
    $name = 'allow-local-' + $ClientIp.Replace('.', '-')
    $arguments = @('--subscription', $context.Subscription, '--resource-group', $context.Group, '--server-name', $server)
    $existing = Invoke-JavaDeploymentTool az (@('postgres', 'flexible-server', 'firewall-rule', 'list') + $arguments +
        @('--query', "[?name=='$name'].[startIpAddress,endIpAddress]", '--output', 'tsv'))
    if ($existing) {
        if ("$existing" -cne "$ClientIp`t$ClientIp") { throw "Rule $name exists with a different range; it will not be overwritten." }
        Write-JavaDeploymentMessage PASS "The individual client IP is already allowed: $ClientIp"
        return
    }
    Confirm-JavaDeploymentChange "Add $name on PostgreSQL $server for $ClientIp only? Existing rules will be preserved."
    $null = Invoke-JavaDeploymentTool az (@('postgres', 'flexible-server', 'firewall-rule', 'create') + $arguments +
        @('--name', $name, '--start-ip-address', $ClientIp, '--end-ip-address', $ClientIp, '--output', 'none'))
    Write-JavaDeploymentMessage PASS "Registered client IP: $ClientIp"
}

function Invoke-JavaDatabaseSql {
    param([string]$Phase, [string]$SqlPath)
    if (-not $SqlPath) {
        $SqlPath = if ($Phase -eq 'users') { 'infra/db/bootstrap-identities.sql' } else { 'infra/db/initialize-image-metadata.sql' }
    }
    $context = Get-JavaDeploymentContext
    if (-not (Test-Path -LiteralPath $SqlPath -PathType Leaf)) { throw "SQL file not found: $SqlPath" }
    $sql = Get-Content -Raw -LiteralPath $SqlPath -ErrorAction Stop
    if ($sql -match '(?m)^\s*\\prompt|migration_identity') {
        throw 'Review the SQL in workshop step 5: use psql variables, no \prompt or migration identity. No SQL was run.'
    }
    if (-not $env:PGSSLROOTCERT -or -not (Test-Path -LiteralPath $env:PGSSLROOTCERT -PathType Leaf) -or
        (Get-Item -LiteralPath $env:PGSSLROOTCERT).Length -eq 0) { throw 'Set PGSSLROOTCERT to the prepared CA bundle first.' }
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) { throw 'Required tool not found: psql' }
    $context = Get-JavaDatabaseInfo $context
    Show-JavaDatabaseInfo $context
    $signedIn = Invoke-JavaDeploymentTool az @('ad', 'signed-in-user', 'show', '--query', 'id', '--output', 'tsv')
    if (-not $signedIn -or "$signedIn" -cne (Get-JavaDeploymentValue POSTGRESQL_ADMIN_OBJECT_ID)) {
        throw 'The signed-in Azure CLI user is not the reviewed Entra administrator.'
    }
    $database = if ($Phase -eq 'users') { 'postgres' } else { $context.Database }
    Confirm-JavaDeploymentChange "Execute reviewed SQL $SqlPath on $($context.HostName) / $database as $($context.Admin)? This changes DB objects and permissions; it is not automatically undone or retried."
    $previousPassword = $env:PGPASSWORD
    $previousSslMode = $env:PGSSLMODE
    try {
        $token = Invoke-JavaDeploymentTool az @('account', 'get-access-token', '--subscription', $context.Subscription,
            '--resource-type', 'oss-rdbms', '--query', 'accessToken', '--output', 'tsv')
        if (-not $token -or @($token).Count -ne 1 -or "$token" -match '\s') { throw 'Token acquisition did not return one token.' }
        $env:PGPASSWORD = "$token"
        $env:PGSSLMODE = 'verify-full'
        $verifySchema = if ($Phase -eq 'schema') { 'true' } else { 'false' }
        $verification = Join-Path $PSScriptRoot 'java-db-permissions.sql'
        $arguments = @('--no-psqlrc', '--no-password', '--host', $context.HostName, '--dbname', $database, '--username', $context.Admin,
            '--set', 'ON_ERROR_STOP=on', '--set', "web_identity_name=$($context.Web)",
            '--set', "worker_identity_name=$($context.Worker)", '--set', "database_name=$($context.Database)",
            '--set', "verify_schema=$verifySchema", '--file', $SqlPath, '--file', $verification)
        & psql @arguments | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'SQL or permission verification failed; changes may be partially applied. Inspect the database before retrying.' }
    }
    finally {
        $env:PGPASSWORD = $previousPassword
        $env:PGSSLMODE = $previousSslMode
        $token = $null
    }
    Write-JavaDeploymentMessage PASS 'SQL and effective permission checks completed. Review the printed roles and grants for unexpected inheritance.'
}

function Test-JavaDeploymentStatus {
    $context = Get-JavaDeploymentContext
    $failed = $false
    $webUrl = $null
    foreach ($role in @('WEB', 'WORKER')) {
        $app = Get-JavaDeploymentValue "${role}_CONTAINER_APP_NAME"
        $arguments = @('--subscription', $context.Subscription, '--resource-group', $context.Group, '--name', $app)
        $json = Invoke-JavaDeploymentTool az (@('containerapp', 'show') + $arguments + @('--query',
            '{state:properties.provisioningState,latest:properties.latestRevisionName,ready:properties.latestReadyRevisionName,ingress:properties.configuration.ingress}', '--output', 'json'))
        $state = $json | ConvertFrom-Json -ErrorAction Stop
        if (-not $state.latest) { throw "$app has no latest revision." }
        $json = Invoke-JavaDeploymentTool az (@('containerapp', 'revision', 'show') + $arguments + @('--revision', $state.latest,
            '--query', '{active:properties.active,health:properties.healthState,running:properties.runningState}', '--output', 'json'))
        $revision = $json | ConvertFrom-Json -ErrorAction Stop
        Write-JavaDeploymentMessage INFO "$app`: provisioning=$($state.state) latest=$($state.latest) ready=$($state.ready) active=$($revision.active) health=$($revision.health) running=$($revision.running)"
        if ($state.state -cne 'Succeeded' -or $state.latest -cne $state.ready -or $revision.active -ne $true -or
            $revision.health -cne 'Healthy') { $failed = $true }
        if ($revision.running -cne 'Running' -and -not ($role -eq 'WEB' -and $revision.running -ceq 'ScaleToZero')) { $failed = $true }
        if ($role -eq 'WEB') {
            if ($state.ingress.external -ne $true -or $state.ingress.targetPort -ne 8080 -or
                $state.ingress.fqdn -notmatch '^[A-Za-z0-9.-]+$') { $failed = $true }
            else { $webUrl = 'https://' + $state.ingress.fqdn }
        }
        elseif ($null -ne $state.ingress) {
            Write-JavaDeploymentMessage FAIL 'Worker ingress must be disabled.'
            $failed = $true
        }
        Invoke-JavaDeploymentTool az (@('containerapp', 'logs', 'show') + $arguments + @('--type', 'system', '--tail', '20'))
    }
    if ($webUrl) {
        Write-JavaDeploymentMessage INFO "Checking web HTTP availability: $webUrl"
        $response = Invoke-WebRequest -Uri $webUrl -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) { $failed = $true }
    }
    Write-JavaDeploymentMessage MANUAL 'Upload, DB permissions, private Blob access, Service Bus and worker processing require separate approved integration/E2E tests.'
    if ($failed) { throw 'Deployment readiness or HTTP availability checks failed.' }
    Write-JavaDeploymentMessage PASS 'Latest revisions, ingress and HTTP availability checks passed; end-to-end functionality is not verified.'
}

function Invoke-JavaDeployment {
    param([string]$Action, [string]$Value, [switch]$Help, [object[]]$RemainingArguments)
    $ErrorActionPreference = 'Stop'
    if ($Help) {
        'Run from the application root. Firewall: -ClientIp IPv4. SQL: [-SqlPath FILE]. Mutating actions require interactive approval.'
        return
    }
    if ($RemainingArguments.Count -gt 0) { throw 'Unknown arguments.' }
    $previousDynamic = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
    $previousUpgrade = $env:AZURE_AUTO_UPGRADE_ENABLE
    try {
        $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
        $env:AZURE_AUTO_UPGRADE_ENABLE = 'false'
        switch ($Action) {
            certificate { New-JavaDatabaseCertificate }
            firewall { Register-JavaDatabaseClientIp $Value }
            info { Show-JavaDatabaseInfo (Get-JavaDatabaseInfo (Get-JavaDeploymentContext)) }
            users { Invoke-JavaDatabaseSql users $Value }
            schema { Invoke-JavaDatabaseSql schema $Value }
            status { Test-JavaDeploymentStatus }
            default { throw 'Unknown deployment action.' }
        }
    }
    finally {
        $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = $previousDynamic
        $env:AZURE_AUTO_UPGRADE_ENABLE = $previousUpgrade
    }
}
