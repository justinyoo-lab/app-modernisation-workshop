. (Join-Path $PSScriptRoot '..\scripts\powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args
if ($bootstrap.Handled) { exit $bootstrap.Code }
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\java-deployment.ps1')
$fixture = Join-Path $root ('.test-output\deployment-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture -Force
$savedPassword = $env:PGPASSWORD
$savedRoot = $env:PGSSLROOTCERT
$savedMode = $env:PGSSLMODE
$script:Passed = 0
$script:Calls = [Collections.Generic.List[string]]::new()
$script:Approved = $true
$script:Interactive = $true
$script:Case = 'success'
function Assert-Deployment([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}
function Assert-DeploymentFailure([scriptblock]$Action, [string]$Name) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-Deployment $failed $Name
}
function Test-JavaDeploymentInteractive { return $script:Interactive }
function Read-Host { if ($script:Approved) { 'APPLY' } else { 'no' } }
function Invoke-JavaDeploymentTool {
    param([string]$Name, [string[]]$Arguments)
    $call = "$Name $($Arguments -join ' ')"
    $script:Calls.Add($call)
    if ($script:Case -eq 'query-failure') { throw 'Fixture query failure' }
    if ($Name -eq 'azd') {
        switch ($Arguments[-1]) {
            AZURE_SUBSCRIPTION_ID { 'subscription-fixture' }
            AZURE_RESOURCE_GROUP { 'rg-fixture' }
            POSTGRESQL_SERVER { 'pg-fixture' }
            POSTGRESQL_DATABASE { 'assets_manager' }
            POSTGRESQL_ADMIN_NAME { 'admin-fixture' }
            POSTGRESQL_ADMIN_OBJECT_ID { 'admin-object' }
            WEB_CONTAINER_APP_NAME { 'web-fixture' }
            WORKER_CONTAINER_APP_NAME { 'worker-fixture' }
            default { throw "Unexpected azd lookup: $call" }
        }
    }
    elseif ($call -like 'az account show *') { 'subscription-fixture' }
    elseif ($call -like 'az ad signed-in-user show *') {
        if ($script:Case -eq 'wrong-admin') { 'other-object' } else { 'admin-object' }
    }
    elseif ($call -like 'az account get-access-token *') {
        if ($script:Case -eq 'empty-token') { return }
        'fixture-secret-token'
    }
    elseif ($call -like 'az postgres flexible-server show *') { 'pg-fixture.postgres.database.azure.com' }
    elseif ($call -like 'az *firewall-rule list *') {
        if ($script:Case -eq 'existing-rule') { "203.0.113.7`t203.0.113.7" }
        elseif ($script:Case -eq 'conflicting-rule') { "203.0.113.1`t203.0.113.10" }
    }
    elseif ($call -like 'az *firewall-rule create *') { }
    elseif ($call -like 'az containerapp show *identity.userAssignedIdentities*') {
        switch ($script:Case) {
            empty-identity { 'null' }
            multiple-identities { '{"/ids/one":{},"/ids/two":{}}' }
            malformed-identity { 'not-json' }
            default { '{"/ids/single":{}}' }
        }
    }
    elseif ($call -like 'az identity show *') {
        if ($script:Case -ne 'empty-name') { 'identity-fixture' }
    }
    elseif ($call -like 'az containerapp show *') {
        $worker = $Arguments -contains 'worker-fixture'
        $ready = if ($script:Case -eq 'stale-revision') { 'previous' } else { 'latest' }
        @{
            state = 'Succeeded'; latest = 'latest'; ready = $ready
            ingress = $(if (-not $worker -or $script:Case -eq 'worker-ingress') {
                @{ external = $true; targetPort = 8080; fqdn = 'web.example.test' }
            })
        } | ConvertTo-Json -Depth 4 -Compress
    }
    elseif ($call -like 'az containerapp revision show *') {
        @{
            active = $true
            health = $(if ($script:Case -eq 'unhealthy') { 'Unhealthy' } else { 'Healthy' })
            running = $(if ($script:Case -eq 'web-scaled-down' -and $Arguments -contains 'web-fixture') { 'ScaleToZero' } else { 'Running' })
        } | ConvertTo-Json -Compress
    }
    elseif ($call -like 'az containerapp logs show *') { 'fixture system event' }
    else { throw "Unexpected call: $call" }
}
function psql {
    $script:Calls.Add("psql $($args -join ' ')")
    Assert-Deployment ($env:PGPASSWORD -ceq 'fixture-secret-token') 'token supplied only in environment'
    Assert-Deployment ($env:PGSSLMODE -ceq 'verify-full') 'TLS verification is enforced'
    Assert-Deployment (($args -join ' ') -notmatch 'fixture-secret-token') 'no token in arguments'
    $global:LASTEXITCODE = if ($script:Case -eq 'sql-failure') { 1 } else { 0 }
}
function Invoke-WebRequest {
    [CmdletBinding()]
    param($Uri, $TimeoutSec, $MaximumRedirection)
    if ("$Uri" -match 'cacerts.digicert.com|microsoft.com/pkiops') {
        if ($script:Case -eq 'download-failure') { throw 'Fixture download failure' }
        return @{ Content = $script:CertificateBytes }
    }
    if ($script:Case -eq 'http-failure') { throw 'Fixture HTTP failure' }
    return @{ StatusCode = $(if ($script:Case -eq 'http-redirect') { 302 } else { 200 }) }
}
try {
    Push-Location $fixture
    Set-Content azure.yaml 'name: fixture'
    Set-Content users.sql "SELECT :'web_identity_name', :'worker_identity_name', :'database_name';"
    Set-Content roots.pem 'fixture-ca'
    $env:PGSSLROOTCERT = Join-Path $fixture 'roots.pem'
    $env:PGPASSWORD = 'previous-password'
    $env:PGSSLMODE = 'previous-mode'
    $context = Get-JavaDatabaseInfo (Get-JavaDeploymentContext)
    Assert-Deployment ($context.Web -eq 'identity-fixture' -and $context.Database -eq 'assets_manager') 'DB info'
    foreach ($case in @('empty-identity', 'multiple-identities', 'malformed-identity', 'empty-name', 'query-failure')) {
        $script:Case = $case
        Assert-DeploymentFailure { Get-JavaDatabaseInfo (Get-JavaDeploymentContext) } $case
    }
    $script:Case = 'success'
    foreach ($ip in @('', '0.0.0.0', '255.255.255.255', '256.1.1.1', '1.2.3', '1.2.3.04', '::1')) {
        Assert-DeploymentFailure { Register-JavaDatabaseClientIp $ip } "invalid IP: $ip"
    }
    $script:Calls.Clear()
    $script:Approved = $false
    Assert-DeploymentFailure { Register-JavaDatabaseClientIp '203.0.113.7' } 'declined firewall change'
    Assert-Deployment (-not ($script:Calls -like '*firewall-rule create*')) 'no denied mutation'
    $script:Approved = $true
    $script:Interactive = $false
    Assert-DeploymentFailure { Register-JavaDatabaseClientIp '203.0.113.7' } 'noninteractive firewall denied'
    $script:Interactive = $true
    Register-JavaDatabaseClientIp '203.0.113.7'
    Assert-Deployment (@($script:Calls -like '*firewall-rule create*').Count -eq 1) 'approved single-IP change'
    $script:Case = 'existing-rule'
    Register-JavaDatabaseClientIp '203.0.113.7'
    Assert-Deployment (@($script:Calls -like '*firewall-rule create*').Count -eq 1) 'existing rule does not mutate'
    $script:Case = 'conflicting-rule'
    Assert-DeploymentFailure { Register-JavaDatabaseClientIp '203.0.113.7' } 'conflicting rule preserved'
    $script:Case = 'success'
    Invoke-JavaDatabaseSql users 'users.sql'
    Assert-Deployment (@($script:Calls -like 'psql *')[-1] -match '--dbname postgres') 'bootstrap uses postgres'
    Invoke-JavaDatabaseSql schema 'users.sql'
    Assert-Deployment (@($script:Calls -like 'psql *')[-1] -match '--dbname assets_manager') 'schema uses application database'
    Assert-Deployment (@($script:Calls -like 'psql *')[-1] -match '--set verify_schema=true .*--file .*java-db-permissions.sql') 'effective permission verification follows SQL'
    foreach ($case in @('sql-failure', 'empty-token', 'wrong-admin')) {
        $script:Case = $case
        Assert-DeploymentFailure { Invoke-JavaDatabaseSql schema 'users.sql' } $case
        Assert-Deployment ($env:PGPASSWORD -ceq 'previous-password' -and $env:PGSSLMODE -ceq 'previous-mode') 'credential environment restored'
    }
    $script:Case = 'success'
    Set-Content users.sql "\prompt 'Web name' web_identity_name"
    Assert-DeploymentFailure { Invoke-JavaDatabaseSql users 'users.sql' } 'legacy prompt SQL rejected before execution'
    foreach ($case in @('stale-revision', 'unhealthy', 'worker-ingress', 'http-failure', 'http-redirect')) {
        $script:Case = $case
        Assert-DeploymentFailure { Test-JavaDeploymentStatus } $case
    }
    $script:Case = 'success'
    Test-JavaDeploymentStatus | Out-Null
    $script:Case = 'web-scaled-down'
    Test-JavaDeploymentStatus | Out-Null
    $script:Case = 'success'
    Assert-Deployment (-not ($script:Calls -match 'logs show.*--follow')) 'logs are bounded'
    $key = [Security.Cryptography.RSA]::Create(2048)
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=Workshop test CA', $key, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(1))
    $script:CertificateBytes = $certificate.RawData
    $caPath = @(New-JavaDatabaseCertificate)
    Assert-Deployment ($caPath.Count -eq 1 -and (Test-Path -LiteralPath $caPath[0])) 'certificate stdout is one path'
    Assert-Deployment ([regex]::Matches((Get-Content -Raw -LiteralPath $caPath[0]), 'BEGIN CERTIFICATE').Count -eq 2) 'two roots in PEM bundle'
    Remove-Item -LiteralPath (Split-Path $caPath[0]) -Recurse -Force
    $script:Case = 'download-failure'
    Assert-DeploymentFailure { New-JavaDatabaseCertificate } 'CA download failure never returns a path'
    $certificate.Dispose()
    $key.Dispose()
    $delegation = Join-Path $fixture 'certificate capture'
    $null = New-Item -ItemType Directory -Path $delegation
    foreach ($name in @('prepare-java-db-root-cert.ps1', 'powershell-bootstrap.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root "scripts\$name") -Destination $delegation
    }
    $encoding = [Text.UTF8Encoding]::new($true)
    [IO.File]::WriteAllText((Join-Path $delegation 'java-deployment.ps1'), @'
function Invoke-JavaDeployment { 'C:\fixture path\roots.pem' }
function Write-JavaDeploymentMessage { param($Status, $Message); [Console]::Error.WriteLine($Message) }
'@, $encoding)
    [IO.File]::WriteAllText((Join-Path $delegation 'capture.ps1'), @'
$global:LASTEXITCODE = 42
$result = @(& (Join-Path $PSScriptRoot 'prepare-java-db-root-cert.ps1'))
if ($LASTEXITCODE -ne 0 -or $result.Count -ne 1 -or $result[0] -cne 'C:\fixture path\roots.pem') { exit 1 }
'@, $encoding)
    $executables = @((Join-Path $PSHOME 'pwsh'))
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { $executables += 'powershell.exe' }
    foreach ($executable in $executables) {
        & $executable -NoLogo -NoProfile -File (Join-Path $delegation 'capture.ps1')
        Assert-Deployment ($LASTEXITCODE -eq 0) "certificate stdout and success exit across delegation: $executable"
    }
    [IO.File]::WriteAllText((Join-Path $delegation 'java-deployment.ps1'), @'
function Invoke-JavaDeployment { throw 'Fixture download failure' }
function Write-JavaDeploymentMessage { param($Status, $Message); [Console]::Error.WriteLine($Message) }
'@, $encoding)
    [IO.File]::WriteAllText((Join-Path $delegation 'capture.ps1'), @'
$result = @(& (Join-Path $PSScriptRoot 'prepare-java-db-root-cert.ps1'))
if ($LASTEXITCODE -ne 1 -or $result.Count -ne 0) { exit 1 }
exit 0
'@, $encoding)
    foreach ($executable in $executables) {
        & $executable -NoLogo -NoProfile -File (Join-Path $delegation 'capture.ps1')
        Assert-Deployment ($LASTEXITCODE -eq 0) "certificate failure forwards nonzero without stdout: $executable"
    }
}
finally {
    Pop-Location
    $env:PGPASSWORD = $savedPassword
    $env:PGSSLROOTCERT = $savedRoot
    $env:PGSSLMODE = $savedMode
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
Write-Host "PASS: $script:Passed Java deployment helper assertions (mocked tools only)"
