<#
.SYNOPSIS
  Deploy the Bicep infrastructure for the assets-manager web/worker workload using Azure CLI.

.DESCRIPTION
  This script is NOT executed by the "007-prepare-bicep-and-db-init" modernization task.
  It is provided for the participant/operator to run manually, after reviewing the
  generated templates, as described in infra/README.md and the plan's
  "Separate DB initialization and participant azd procedure" section.

.PARAMETER ResourceGroupName
  Target resource group (created if it does not already exist).

.PARAMETER Location
  Azure region. Must be one of: centralus, swedencentral, southeastasia, westus3, westcentralus
  (regions with available PostgreSQL Flexible Server quota at template-authoring time).

.PARAMETER EnvironmentName
  Short environment name used to derive the uniqueString resource token (e.g. "assetsdev").

.PARAMETER DbOperatorPrincipalName
  Microsoft Entra principal name (UPN/group) of the one-time database operator who will run
  infra/database/init.sql. Distinct from the workload managed identities created by this template.

.PARAMETER DbOperatorObjectId
  Microsoft Entra object ID of the database operator principal above.

.PARAMETER DbOperatorPrincipalType
  One of User, Group, ServicePrincipal. Defaults to User.

.EXAMPLE
  ./deploy.ps1 -ResourceGroupName assets-manager-rg -Location centralus -EnvironmentName assetsdev `
      -DbOperatorPrincipalName operator@contoso.com -DbOperatorObjectId <guid>
#>
param(
  [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
  [Parameter(Mandatory = $false)] [string] $Location = "centralus",
  [Parameter(Mandatory = $true)] [string] $EnvironmentName,
  [Parameter(Mandatory = $true)] [string] $DbOperatorPrincipalName,
  [Parameter(Mandatory = $true)] [string] $DbOperatorObjectId,
  [Parameter(Mandatory = $false)] [string] $DbOperatorPrincipalType = "User"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==========================================="
Write-Host "Validating Bicep templates (no resources are created by this step)"
Write-Host "==========================================="
az bicep build --file (Join-Path $ScriptDir "main.bicep")

Write-Host "==========================================="
Write-Host "Creating resource group (if it does not already exist)"
Write-Host "==========================================="
az group create --name $ResourceGroupName --location $Location

Write-Host "==========================================="
Write-Host "What-if preview of the deployment (no resources are created by this step)"
Write-Host "==========================================="
az deployment group what-if `
  --resource-group $ResourceGroupName `
  --template-file (Join-Path $ScriptDir "main.bicep") `
  --parameters environmentName=$EnvironmentName location=$Location `
               dbOperatorPrincipalName=$DbOperatorPrincipalName `
               dbOperatorObjectId=$DbOperatorObjectId `
               dbOperatorPrincipalType=$DbOperatorPrincipalType

$Confirm = Read-Host "Review the what-if output above. Proceed with deployment? [y/N]"
if ($Confirm -ne "y" -and $Confirm -ne "Y") {
  Write-Host "Aborted. No resources were created."
  exit 0
}

Write-Host "==========================================="
Write-Host "Deploying infrastructure (Container Apps, PostgreSQL, Service Bus, Blob Storage, managed identities)"
Write-Host "==========================================="
az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file (Join-Path $ScriptDir "main.bicep") `
  --parameters environmentName=$EnvironmentName location=$Location `
               dbOperatorPrincipalName=$DbOperatorPrincipalName `
               dbOperatorObjectId=$DbOperatorObjectId `
               dbOperatorPrincipalType=$DbOperatorPrincipalType

Write-Host "==========================================="
Write-Host "Deployment complete."
Write-Host "Next steps (each requires separate, explicit operator approval):"
Write-Host "  1. Review and run infra/database/init.sql against the new PostgreSQL Flexible Server"
Write-Host "     (see infra/database/README.md for exact commands). This script does NOT run it."
Write-Host "  2. Build web/worker container images locally and push them to the deployed registry."
Write-Host "  3. az containerapp update --image <acr-login-server>/web:<tag> ... (and worker)."
Write-Host "==========================================="
