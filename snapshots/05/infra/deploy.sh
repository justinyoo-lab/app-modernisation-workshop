#!/usr/bin/env bash
# Deploy the Bicep infrastructure for the assets-manager web/worker workload using Azure CLI.
#
# This script is NOT executed by the "007-prepare-bicep-and-db-init" modernization task.
# It is provided for the participant/operator to run manually, after reviewing the
# generated templates, as described in infra/README.md and the plan's
# "Separate DB initialization and participant azd procedure" section.
#
# Prerequisites:
#   - az login (as a principal with Contributor + User Access Administrator on the target
#     resource group, so it can create role assignments)
#   - az bicep install (or any recent az cli with the bicep extension)
#
# Usage:
#   ./deploy.sh -g <resourceGroupName> -l <location> -e <environmentName> \
#               -o <dbOperatorPrincipalName> -i <dbOperatorObjectId> [-t <dbOperatorPrincipalType>]

set -euo pipefail

ResourceGroupName=""
Location="centralus"
EnvironmentName=""
DbOperatorPrincipalName=""
DbOperatorObjectId=""
DbOperatorPrincipalType="User"

while getopts "g:l:e:o:i:t:" opt; do
  case $opt in
    g) ResourceGroupName="$OPTARG" ;;
    l) Location="$OPTARG" ;;
    e) EnvironmentName="$OPTARG" ;;
    o) DbOperatorPrincipalName="$OPTARG" ;;
    i) DbOperatorObjectId="$OPTARG" ;;
    t) DbOperatorPrincipalType="$OPTARG" ;;
    *) echo "Unknown option"; exit 1 ;;
  esac
done

if [[ -z "$ResourceGroupName" || -z "$EnvironmentName" || -z "$DbOperatorPrincipalName" || -z "$DbOperatorObjectId" ]]; then
  echo "Usage: ./deploy.sh -g <resourceGroupName> -l <location> -e <environmentName> -o <dbOperatorPrincipalName> -i <dbOperatorObjectId> [-t <dbOperatorPrincipalType>]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==========================================="
echo "Validating Bicep templates (no resources are created by this step)"
echo "==========================================="
az bicep build --file "$SCRIPT_DIR/main.bicep"

echo "==========================================="
echo "Creating resource group (if it does not already exist)"
echo "==========================================="
az group create --name "$ResourceGroupName" --location "$Location"

echo "==========================================="
echo "What-if preview of the deployment (no resources are created by this step)"
echo "==========================================="
az deployment group what-if \
  --resource-group "$ResourceGroupName" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters environmentName="$EnvironmentName" location="$Location" \
               dbOperatorPrincipalName="$DbOperatorPrincipalName" \
               dbOperatorObjectId="$DbOperatorObjectId" \
               dbOperatorPrincipalType="$DbOperatorPrincipalType"

read -r -p "Review the what-if output above. Proceed with deployment? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted. No resources were created."
  exit 0
fi

echo "==========================================="
echo "Deploying infrastructure (Container Apps, PostgreSQL, Service Bus, Blob Storage, managed identities)"
echo "==========================================="
az deployment group create \
  --resource-group "$ResourceGroupName" \
  --template-file "$SCRIPT_DIR/main.bicep" \
  --parameters environmentName="$EnvironmentName" location="$Location" \
               dbOperatorPrincipalName="$DbOperatorPrincipalName" \
               dbOperatorObjectId="$DbOperatorObjectId" \
               dbOperatorPrincipalType="$DbOperatorPrincipalType"

echo "==========================================="
echo "Deployment complete."
echo "Next steps (each requires separate, explicit operator approval):"
echo "  1. Review and run infra/database/init.sql against the new PostgreSQL Flexible Server"
echo "     (see infra/database/README.md for exact commands). This script does NOT run it."
echo "  2. Build web/worker container images locally and push them to the deployed registry."
echo "  3. az containerapp update --image <acr-login-server>/web:<tag> ... (and worker)."
echo "==========================================="
