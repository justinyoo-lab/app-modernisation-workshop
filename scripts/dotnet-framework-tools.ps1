. (Join-Path $PSScriptRoot 'powershell-bootstrap.ps1')
$bootstrap = Initialize-WorkshopScript -ScriptPath $PSCommandPath -BoundParameters @{} -RemainingArguments $args -DotSourced ($MyInvocation.InvocationName -eq '.')
if ($bootstrap.Handled) { exit $bootstrap.Code }

function Invoke-FrameworkProbe {
    param([string]$File, [string[]]$Arguments)
    try {
        $text = (& $File @Arguments 2>&1 | Out-String).Trim()
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text }
    }
    catch { return [pscustomobject]@{ Code = 127; Text = $_.Exception.Message } }
}

function Get-DotnetFrameworkBuildTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $result = Invoke-FrameworkProbe $vswhere @('-products', '*', '-version', '[17.0,19.0)', '-requires', 'Microsoft.Component.MSBuild', '-format', 'json', '-utf8')
    if ($result.Code -ne 0) { throw 'Could not run vswhere from Visual Studio Installer.' }
    try { $instances = @($result.Text | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'Could not parse vswhere output.' }
    foreach ($instance in ($instances | Sort-Object { [version]$_.installationVersion } -Descending)) {
        if (-not $instance.installationPath) { continue }
        $major = ([version]$instance.installationVersion).Major
        $msbuild = Join-Path $instance.installationPath 'MSBuild\Current\Bin\MSBuild.exe'
        $webTools = Join-Path $instance.installationPath "MSBuild\Microsoft\VisualStudio\v$major.0"
        if ((Test-Path -LiteralPath $msbuild -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $webTools 'WebApplications\Microsoft.WebApplication.targets') -PathType Leaf)) {
            return [pscustomobject]@{ MSBuild = $msbuild; WebTools = $webTools; Version = "$major.0" }
        }
    }
    throw 'MSBuild.exe and WebApplications\Microsoft.WebApplication.targets from VS 2022/2026 IDE or Build Tools are required. Check the ASP.NET web build components.'
}

function Get-WorkshopIisExpress {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        $exe = Join-Path $base 'IIS Express\iisexpress.exe'
        $template = Join-Path $base 'IIS Express\AppServer\applicationhost.config'
        if ((Test-Path -LiteralPath $exe -PathType Leaf) -and (Test-Path -LiteralPath $template -PathType Leaf)) {
            return [pscustomobject]@{ Exe = $exe; Template = $template }
        }
    }
    throw 'The IIS Express executable and AppServer\applicationhost.config template are required.'
}
