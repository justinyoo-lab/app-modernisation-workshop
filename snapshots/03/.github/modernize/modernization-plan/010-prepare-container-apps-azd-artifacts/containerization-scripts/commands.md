# Local build/scan/smoke-check commands (reference only)

These are the exact local commands run for task 010-prepare-container-apps-azd-artifacts.
All commands were run from the `java/` repository root. No remote build, ACR Tasks, image
push, or `azd provision`/`azd deploy` was performed.

## Build (local Docker engine only)
```powershell
docker build -f web\Dockerfile -t assets-manager-web:v1 -t assets-manager-web:latest `
  --platform linux/amd64 .

docker build -f worker\Dockerfile -t assets-manager-worker:v1 -t assets-manager-worker:latest `
  --platform linux/amd64 .
```

## Vulnerability scan
Performed via the `appmod-scan-docker-image` tool (scanner: osv, scanType: vulnerability,
severity: HIGH) against `assets-manager-web:v1` and `assets-manager-worker:v1`. Both passed
with no significant vulnerabilities.

## Local smoke checks (dummy, non-resolving Azure endpoints; no real Azure resources touched)
```powershell
docker run --rm --name smoke-web `
  -e SERVICE_BUS_NAMESPACE=dummy.servicebus.windows.net `
  -e AZURE_STORAGE_BLOB_ENDPOINT=https://dummy.blob.core.windows.net `
  -e POSTGRESQL_SERVER=dummy -e POSTGRESQL_USERNAME=dummy `
  assets-manager-web:v1

docker run --rm --name smoke-worker `
  -e SERVICE_BUS_NAMESPACE=dummy.servicebus.windows.net `
  -e AZURE_STORAGE_BLOB_ENDPOINT=https://dummy.blob.core.windows.net `
  -e POSTGRESQL_SERVER=dummy -e POSTGRESQL_USERNAME=dummy `
  assets-manager-worker:v1
```

## azd project validation (no environment created, no provisioning)
```powershell
azd show
```
Output confirmed both `web` and `worker` services are recognized from the new `azure.yaml`,
with no environment created and the application not yet provisioned.
