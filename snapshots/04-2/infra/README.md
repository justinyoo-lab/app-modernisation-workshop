# Infrastructure: assets-manager (web + worker) on Azure

This folder contains Bicep templates to provision the Azure infrastructure for
the modernized `assets-manager` application (Java 25 / Spring Boot 4.1.2,
`web` and `worker` modules), per modernization task
`007-prepare-bicep-and-db-init`.

> **This task does not provision any resources.** `provision=false` for this
> task; templates were validated locally only (`az bicep build`). Deployment
> is a separate, manually-approved step performed by the participant/operator
> using `deploy.sh` / `deploy.ps1` below.

## Resources provisioned by `main.bicep`

| Resource | Bicep module | Purpose |
|---|---|---|
| 2× User-Assigned Managed Identity | `modules/identity.bicep` | One per workload (`web`, `worker`); used for ACR pull and all Azure service authentication (PostgreSQL, Service Bus, Blob Storage). No secrets/keys are ever generated for these identities. |
| Azure Container Registry (Basic) | `modules/containerregistry.bicep` | Hosts web/worker container images. `AcrPull` role assigned to each workload identity (admin user disabled). |
| Log Analytics workspace | `modules/loganalytics.bicep` | Backs the Container Apps environment's log destination. |
| Container Apps (managed) Environment | `modules/containerappenv.bicep` | Shared environment for the web and worker Container Apps, wired to Log Analytics. |
| Container App: web | `modules/containerapp.bicep` | Linux Container App, external HTTPS ingress (CORS enabled), pulls images via its own managed identity. Starts from the mandatory placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`; the real image is published and swapped in by a separate, out-of-scope deploy step. |
| Container App: worker | `modules/containerapp.bicep` | Linux Container App, **no ingress** (background Service Bus consumer only), same placeholder-image/identity pattern as web. |
| PostgreSQL Flexible Server (v17) | `modules/postgresql.bicep` | Microsoft Entra-only authentication (`activeDirectoryAuth=Enabled`, `passwordAuth=Disabled`) — there is no PostgreSQL password at all. Firewall rule allows Azure services (`0.0.0.0`). The JDBC URL uses `sslmode=verify-full` and the Java truststore. |
| Service Bus namespace (Standard) + `image-processing` queue | `modules/servicebus.bicep` | `disableLocalAuth=true` (no SAS connection strings). Least-privilege Data Sender/Receiver roles scoped to the single queue. |
| Storage Account (private) + `assets` blob container | `modules/storage.bicep` | `allowSharedKeyAccess=false`, `allowBlobPublicAccess=false`, container `publicAccess=None`. Least-privilege `Storage Blob Data Contributor` scoped to the single container. |

Key Vault was **not** provisioned: every Azure service connection in this
application (PostgreSQL, Service Bus, Blob Storage) uses passwordless Azure
Managed Identity authentication (see `web`/`worker`
`src/main/resources/application.properties`, tasks 003–006), so there are no
application secrets to store. Per the IaC rules, Key Vault should only be
introduced when the application actually has secrets.

## Database principal grants vs. ARM roles (kept distinct)

- **ARM/control-plane roles** (who can manage the Azure *resources*): AcrPull,
  Service Bus Data Sender/Receiver, Storage Blob Data Contributor — all
  defined as `Microsoft.Authorization/roleAssignments` in the Bicep modules
  above, scoped to the narrowest possible resource (queue/container, not
  namespace/account).
- **Database-level principal grants** (who can read/write rows inside
  PostgreSQL): defined separately in `infra/database/init.sql`, run manually
  by a distinct **database operator** identity (the server's Microsoft Entra
  admin, `dbOperatorPrincipalName`/`dbOperatorObjectId` parameters), never by
  this Bicep template and never by the workload managed identities themselves.

These two authorization planes never overlap: an ARM role never grants SQL
privileges, and a SQL `GRANT` never grants ARM/control-plane access.

## Parameters (`main.parameters.json`)

| Parameter | Description |
|---|---|
| `environmentName` | Short name used to derive the `uniqueString` resource token for all resource names. |
| `location` | One of `centralus`, `swedencentral`, `southeastasia`, `westus3`, `westcentralus` — the regions with confirmed `Microsoft.DBforPostgreSQL/flexibleServers` quota at template-authoring time (checked via `appmod-get-available-region-sku`; `eastus2`, used by the legacy `scripts/deploy-to-azure.*` script, did **not** have confirmed PostgreSQL Flexible Server quota and was intentionally not reused). |
| `dbOperatorPrincipalName` / `dbOperatorObjectId` / `dbOperatorPrincipalType` | Identifies the one-time database operator who will later run `infra/database/init.sql`. Must be a human/group/service-principal distinct from the `web`/`worker` workload managed identities. |

No password, connection-string, or other secret parameter exists anywhere in
this template.

## Outputs

`main.bicep` emits only non-secret values: registry login server, Container
Apps environment/app names and FQDNs, workload managed identity names/client
IDs, PostgreSQL server name/FQDN/database name, Service Bus namespace/queue
name, and storage account name/blob endpoint/container name. These are the
same values referenced as placeholders (`${POSTGRESQL_SERVER}`,
`${SERVICE_BUS_NAMESPACE}`, `${AZURE_STORAGE_BLOB_ENDPOINT}`, etc.) in
`web`/`worker` `application.properties`, and are wired automatically as
Container App environment variables in `modules/containerapp.bicep`.

## 메시지와 저장소 운영

- Blob 컨테이너는 미리 존재해야 합니다. 앱은 시작 시 존재 여부를 확인하며 생성하지 않습니다.
- 비-dev 업로드는 메타데이터와 발행 요청을 같은 DB 트랜잭션에 기록합니다. 발행 실패는 아웃박스에 남아 재시도되며, 발행 성공 후 DB 커밋 실패 시 중복 전달될 수 있습니다. Blob 저장 후 DB 기록이 실패하면 Blob은 남으므로 로그의 키를 확인해야 합니다.
- `backup` 프로필을 사용할 때는 기존 `image-processing`과 다른 `BACKUP_SERVICE_BUS_QUEUE`를 지정하세요. web은 두 큐에 메시지를 발행하고 backup 큐를 소비합니다. 별도 큐와 그 큐에 대한 web 관리 ID의 Sender·Receiver 권한이 필요합니다. 현재 Bicep은 backup 큐나 해당 권한을 만들지 않습니다.
- dev 업로드는 DB 아웃박스를 사용하지 않습니다. backup 발행이 실패하면 주 큐 발행은 이미 성공했을 수 있으며 오류를 반환합니다.
- 비-dev worker와 web의 원본 키 삭제는 메타데이터 행 잠금으로 직렬화합니다. 이미 생성된 썸네일이 있으면 중복 수신 시 다시 저장하지 않습니다. Blob 작업 중에는 DB 트랜잭션과 잠금이 유지되므로 연결 수와 처리 시간을 고려해야 합니다.
- Blob과 DB는 단일 트랜잭션이 아닙니다. 삭제 중 일부 Blob 작업이 실패하면 오류가 반환되지만 이미 삭제한 Blob은 복원되지 않습니다. dev 경로와 썸네일 키만 직접 삭제하는 경우에는 이 행 잠금이 적용되지 않습니다.

## 인증과 TLS

- 실제 Azure 연결 테스트의 사전 조건과 실행·정리는 [통합 테스트 안내](azure-it.md)를 참고하세요.
- ACA는 기본 설정의 관리 ID를 사용합니다. 로컬에서는 `local` Spring 프로필을 켜서 `DefaultAzureCredential`을 사용하세요. 기존 dev 저장소 동작도 필요하면 `dev,local`을 함께 지정합니다. 사용자 계정과 리소스 권한은 별도로 준비해야 합니다.
- `DefaultAzureCredential`은 환경 자격 증명, 워크로드·관리 ID, 개발 도구 자격 증명 등을 순서대로 시도합니다. 설치된 SDK와 환경에 따라 실제 선택이 달라지며, 환경 변수나 더 높은 우선순위의 Spring 설정은 프로필 설정을 덮어쓸 수 있습니다. [자격 증명 체인](https://learn.microsoft.com/azure/developer/java/sdk/authentication/credential-chains)을 확인하세요.
- PostgreSQL 연결은 인증서와 호스트명을 검증합니다. 실행 환경의 Java truststore에 Azure PostgreSQL 서버의 신뢰된 루트 CA가 있어야 합니다. 인증서 교체와 필요한 CA는 [Microsoft TLS 안내](https://learn.microsoft.com/azure/postgresql/security/security-tls-how-to-connect)를 확인하세요. 시스템 truststore 변경은 자동으로 수행하지 않습니다.
- 비공개 Blob 설정은 사용자의 웹 접근 권한을 보장하지 않습니다. 현재 앱에는 최종 사용자 인증이 없으므로 신뢰할 수 있는 외부 인증 계층을 확인하기 전에는 공개하지 마세요.
- Spring Cloud Azure 7.4.0의 [공식 버전 매핑](https://github.com/Azure/azure-sdk-for-java/blob/main/docs/spring/Spring-Versions-Mapping.md)은 Spring Boot 4.0.x를 명시합니다. 현재 4.1.2 조합의 지원 여부와 Netty 버전 불일치는 미확인입니다.

## Validation performed (local only — no resources were created)

```
az bicep build --file infra/main.bicep
```

completed with no errors or warnings. No `az deployment group create`,
`az deployment group what-if` (which requires a live resource group), or
`azd provision` command was executed as part of this task.

## Deploying later (separate, approved step — not part of this task)

```bash
./infra/deploy.sh -g <resourceGroupName> -l centralus -e <environmentName> \
    -o <dbOperatorPrincipalName> -i <dbOperatorObjectId>
```

```powershell
./infra/deploy.ps1 -ResourceGroupName <resourceGroupName> -Location centralus `
    -EnvironmentName <environmentName> -DbOperatorPrincipalName <name> -DbOperatorObjectId <guid>
```

Both scripts run `az bicep build` and `az deployment group what-if` first and
prompt for confirmation before `az deployment group create`. Neither script
runs `infra/database/init.sql` — see `infra/database/README.md` for that
separate, manually-approved procedure.

## Compliance

See `compliance.md` for a line-by-line mapping of applied IaC rules.
