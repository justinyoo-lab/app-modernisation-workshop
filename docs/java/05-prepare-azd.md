# 5. azd 배포 산출물 준비하기

[전체 목차](../../README.md) | [Java 목차](README.md) | [이전: Azure 서비스 이전](04-migrate-azure-services.md) | [다음: ACA 배포](06-deploy-aca.md) | [문제 해결](08-troubleshooting.md)

## 목표

[실습 3: JDK 25로 업그레이드하기](03-upgrade.md)에서 생성된 Dockerfile, `azure.yaml`, Bicep과 DB 초기화 절차를 검토합니다. 실제 앱 코드와 선택한 컨테이너 엔진에 맞게 필요한 부분을 수정합니다. 이 단계에서는 Azure 리소스를 만들거나 이미지를 게시하지 않습니다.

## 실습 범위

| 단계 | 다루는 내용 | 이 단계에서 하지 않는 작업 |
| --- | --- | --- |
| [실습 3: JDK 25로 업그레이드하기](03-upgrade.md) | Java 업그레이드, Azure 서비스 이전 코드와 배포 산출물 준비, 로컬 빌드 및 모의 테스트 | Azure 리소스 생성, 실제 Azure 연결, 앱 배포 |
| [실습 4: Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md) | 이전된 Azure 서비스 코드와 테스트 검토, 필요한 수정과 로컬 검증 | Azure 리소스 생성과 실제 연결 |
| 실습 5: azd 배포 산출물 준비하기 (이 문서) | Dockerfile, `azure.yaml`, Bicep, DB 초기화 절차와 배포 설정 검토 및 수정 | 프로비저닝, DB 초기화, 이미지 게시, 배포 |
| [실습 6: azd로 ACA에 배포하기](06-deploy-aca.md) | 승인 후 Azure 리소스 프로비저닝, DB 초기화, 로컬 이미지 빌드, 배포와 실제 기능 확인 | 승인하지 않은 리소스나 데이터 변경 |

## 실습 전 확인 사항

[실습 4: Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md)에서 Azure 연동 코드와 테스트를 검토하고 필요한 수정을 마칩니다. 같은 Copilot app 터미널의 **앱 루트**를 계속 사용합니다. [실습 3: JDK 25로 업그레이드하기](03-upgrade.md)에서 기록한 `$before`를 기준으로 Modernize가 자동 커밋한 내용과 아직 커밋하지 않은 변경을 함께 확인합니다.

```bash
git status --short
git log --oneline "$before..HEAD"
git diff "$before..HEAD"
git diff
git diff --cached
```

Git 변경 목록에서 `java/` 앱 밖의 파일(예: `docs/`, `scripts/`)이 변경됐는지 확인합니다. 토큰, 자격 증명, 비공개 키, 연결 문자열 등 비밀정보가 포함됐는지도 살핍니다. Copilot app 채팅에서 Java 검증을 요청할 때는 먼저 해당 셸에서 도우미로 JDK 25를 선택하도록 안내합니다.

## 배포 산출물 요구사항 확인

다음 프롬프트로 생성된 배포 산출물에 요구사항이 반영됐는지 확인합니다. 이미 생성된 산출물은 `azd init --from-code`로 다시 생성하지 않습니다.

DB 도우미 연동은 [실습 6: azd로 ACA에 배포하기](06-deploy-aca.md)에서 사용하는 `../scripts/` 도우미를 기준으로 검토합니다.

```text
`.github/modernize/rulebook/`과 실제 Azure 연동 코드 및 환경 변수 정의를 읽고
현재 앱 루트에 있는 기존 Azure Developer CLI 산출물만 검토해 줘. 파일을 만들거나 변경하지 말고 명령도 실행하지 마.

- **azd 설정:** `azure.yaml`의 `web`과 `worker`가 `language: docker`, `host: containerapp`으로 설정되어 있는지 확인해 줘. 로컬 Docker를 사용하고 `AZD_CONTAINER_RUNTIME=docker`, `docker.remoteBuild: false`, `docker.platform: linux/amd64`로 설정되어 있는지도 확인해 줘. Dockerfile 경로가 실제 파일과 일치하고 빌드 컨텍스트가 앱 루트인지, `language: java`의 자동 JAR 탐색과 혼용하지 않는지 확인해 줘.
- **이미지 빌드:** 두 서비스의 Dockerfile이 JDK 25로 루트 Maven reactor를 빌드하고, Java 25 런타임에서 각각 해당 모듈의 JAR을 실행하는지 확인해 줘.
  실제 이미지 태그와 매니페스트를 확인할 근거, 멀티 스테이지 빌드, root가 아닌 실행 사용자, `.dockerignore`, 필수 설정과 헬스 체크도 살펴봐 줘.
  이미지 태그는 `latest`를 재사용하지 않고 이번 빌드를 식별할 수 있는 고유 값이어야 해.
- **Container Apps:** `web`의 HTTP ingress 포트가 앱의 수신 포트와 일치하고 `worker`의 ingress는 꺼져 있는지 확인해 줘.
  `worker`는 계속 실행되는 컨슈머여야 하며 `minReplicas=1`, `maxReplicas=1`이어야 해. `web`이 scale-to-zero로 설정되어 있다면 콜드 스타트 검증 계획도 확인해 줘.
  초기 프로비저닝용 임시 이미지를 사용한다면 신뢰할 수 있는지, 실제 서비스 이미지로 교체하는 절차가 명시됐는지 확인해 줘. 임시 이미지를 실제 서비스로 오인할 여지도 살펴봐 줘.
- **Azure 리소스와 권한:** Bicep에 ACR Basic, ACA 환경, Log Analytics, PostgreSQL Flexible Server, Service Bus 큐, 비공개 Blob, 관리 ID와 최소 권한이 정의되어 있는지 확인해 줘.
  ACR에서 이미지를 가져올 때 관리 ID를 사용하는지 확인해 줘. 로컬에서 `azd`를 실행하는 계정의 이미지 푸시 권한도 별도로 설명해야 해.
  `az acr build`, ACR Tasks와 원격 빌드는 사용하지 않아야 해.
- **출력과 제외 파일:** `AZURE_CONTAINER_REGISTRY_ENDPOINT`, `AZURE_RESOURCE_GROUP`, `AZURE_WEB_APP_NAME`, `AZURE_WORKER_APP_NAME`, `WEB_URI` 출력과 azd가 서비스를 찾는 데 사용하는 `azd-service-name` 태그 또는 `resourceName`을 확인해 줘.
  Bicep과 `azure.yaml`의 서비스 이름, 태그와 리소스 이름을 대조해 줘. `.azure/`, 비밀정보가 담긴 파일과 빌드 산출물이 Git 및 이미지 빌드 컨텍스트에서 제외되는지도 확인해 줘.
- **통합 테스트 출력:** `AZURE_IT_PG_HOST`, `AZURE_IT_PG_DATABASE`, `AZURE_IT_BLOB_ENDPOINT`, `AZURE_IT_BLOB_CONTAINER`, `AZURE_IT_SERVICEBUS_NAMESPACE`, `AZURE_IT_SERVICEBUS_QUEUE`가 실제 프로비저닝된 테스트 대상을 가리키는지 확인해 줘. 이 값들은 비밀정보 없이 azd 환경에 출력되어야 해.
  스크립트가 앱 큐와 대조할 수 있도록 `AZURE_IT_APP_SERVICEBUS_NAMESPACE`와 `AZURE_IT_APP_SERVICEBUS_QUEUE` 출력도 확인해 줘. 실제 앱의 큐 설정과 일치해야 해.
  서버와 네임스페이스는 FQDN, Blob 엔드포인트는 `https://` URL이어야 해. 큐는 앱의 메시지를 소비하지 않는 테스트 전용 큐여야 해.
  없는 출력이나 리소스는 누락으로 보고하고, 새 리소스와 권한이 필요한 이유 및 비용을 별도로 제시해 줘. 리소스를 만들거나 권한을 변경하지 마.
- **DB 초기화:** 워크숍에서는 로컬 PC에서 Azure CLI에 로그인한 Entra 관리자가 DB 사용자 생성, 테이블 생성과 권한 부여를 모두 수행해야 해. 별도 실행 호스트나 `az login --identity`를 요구하지 않는지 확인해 줘.
  초기화 SQL과 README, 관련 테스트가 이 방식과 일치해야 해. 테이블 소유자는 초기화를 수행한 관리자 DB 역할이어야 해.
  앱은 web/worker 관리 ID로 연결해야 해. web에는 테이블 조회, 추가, 수정, 삭제를, worker에는 조회와 수정만 허용해야 해. 스키마 생성이나 테이블 변경 권한은 주지 마.
  사용하지 않는 마이그레이션 관리 ID의 생성 코드, 매개변수, 출력과 SQL 입력 프롬프트가 남아 있으면 수정 대상으로 보고해 줘.
  새 데모 DB만 대상으로 하고 기존 DB를 삭제하거나 덮어쓰지 않는지도 확인해 줘. 컨트롤 플레인의 RBAC 권한만으로 DB 인증이 가능하다고 판단하지 말고, 실제 DB 작업도 실행하지 마.
- **DB 도우미 연동:** `../scripts/` 도우미에 필요한 azd 출력 `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `POSTGRESQL_SERVER`, `POSTGRESQL_DATABASE`, `POSTGRESQL_ADMIN_NAME`, `POSTGRESQL_ADMIN_OBJECT_ID`, `WEB_CONTAINER_APP_NAME`, `WORKER_CONTAINER_APP_NAME`이 실제 리소스와 연결되는지 확인해 줘.
  `infra/db/bootstrap-identities.sql`과 `infra/db/initialize-image-metadata.sql`은 도우미가 `--set`으로 전달하는 `web_identity_name`, `worker_identity_name`, `database_name`을 사용해야 해. `\prompt`나 마이그레이션 관리 ID 입력은 요구하지 않아야 해.
  SQL 값은 `:'변수명'`, 식별자는 `:"변수명"`으로 안전하게 인용해야 해.
  bootstrap SQL은 `postgres` DB에서 시작해 앱 DB에 연결한 상태로 끝나야 해. schema SQL은 앱 DB에서 실행해야 해.
  변수 이름, 재실행 시 동작과 SQL 오류 시 중단 방식이 README 및 관련 테스트와 일치하는지 확인해 줘. 실제 SQL은 실행하지 마.
- **네트워크와 비용:** 로컬 PC와 ACA에서 DB까지의 네트워크 경로, 구독, 리전, SKU, 비용과 권한을 검토해 줘.
  공개 네트워크를 사용하는 DB는 확인된 클라이언트와 송신(egress) IP만 허용해야 해. ACA 인바운드 고정 IP를 송신 IP로 간주하지 마.
  경로를 확인할 수 없으면 누락 사항, 대안과 비용 승인 필요성을 보고해 줘.
- **훅과 검증:** 앱 루트와 서비스별로 설정된 모든 `azd` 훅(hook)과 호출 스크립트를 검토해 줘. 셸, 실행 위치와 상대 경로를 확인해 줘.
  명령 수준 훅은 앱 루트, 서비스 수준 훅은 `project` 경로를 기준으로 확인해 줘.
  DB 초기화나 자동 배포가 `postprovision`에 숨겨져 있거나, 오류를 무시하는 `continueOnError: true`가 기본값으로 설정되지 않았는지 확인해 줘.
  템플릿 검증과 단위 빌드는 이미 기록된 결과만 확인하고, 결과가 없으면 미검증으로 표시해 줘. 실행하지 않은 통합 테스트도 구분해 줘.
- **제외 범위:** 이미지 게시, 프로비저닝, DB 사용자와 권한 변경, 마이그레이션 및 배포는 하지 마.

각 판단의 근거로 파일 경로와 줄 번호를 제시하고, 누락된 항목은 누락으로, 근거가 없어 확인할 수 없는 항목은 미확인 또는 미검증으로 보고해 줘.
```

## 발견 사항 조치

수정하거나 추가로 확인할 내용이 있으면 같은 Copilot app 채팅에 다음과 같이 요청합니다. Log Analytics나 헬스 프로브 누락 등은 실제 검토에서 발견된 경우에만 조치합니다.

```text
위 검토 결과를 배포 산출물 수정이 필요한 사항, 배포 전 선택이나 승인이 필요한 사항, 실제 Azure 환경에서 검증할 사항으로 구분해 줘.
`azure.yaml`, Dockerfile, Bicep, 훅과 DB 초기화 절차 중 각 항목의 대상과 근거, 영향, 조치 방법을 제시해 줘.
네트워크 경로, 권한과 비용에 관해 결정할 사항과 로컬에서 검증할 수 없는 사항을 구분해 줘.
각 조치에 필요한 로컬 검증과 실제 Azure 연결이 필요한 검증을 나눠 줘.
파일을 변경하거나 명령을 실행하지 마.
```

수정이 필요하면 제안된 범위와 네트워크, 비용 등 선택이 필요한 사항을 검토합니다. 그런 다음 승인한 항목을 명시하고 별도로 수정을 요청합니다.

```text
위에서 승인한 배포 산출물과 관련 테스트, 문서만 수정해 줘.
Java 검증이 필요하면 앱 루트에서 현재 셸에 맞는 `../scripts/`의 `use-java` 도우미로 JDK 25를 선택해 줘.
변경 내용에 필요한 로컬 템플릿 검증을 실행하고, 단위 빌드가 필요하면 같은 셸에서 실행해 줘.
도구 설치, 실제 Azure 연결, 이미지 빌드와 게시, 프로비저닝, DB 변경과 배포는 하지 마.
변경 파일과 검증 결과를 보고하고 실행할 수 없는 검증은 이유와 함께 미검증으로 표시해 줘.
```

수정 후 변경 내용과 검증 결과를 살펴봅니다. 파일이나 리소스를 변경하지 않는 검토를 다시 요청해 문제가 해결됐는지 확인합니다.

로컬에서 확인할 수 없는 Azure 연결과 통합 테스트는 미검증으로 기록합니다. [실습 6: azd로 ACA에 배포하기](06-deploy-aca.md)에서 승인 후 확인합니다. 다음 실습의 진행을 막는 문제가 남아 있다면 먼저 해결합니다.

## 비용과 배포 승인

ACA가 scale-to-zero 상태여도 PostgreSQL, Service Bus, ACR, 로그 및 네트워크 리소스에는 비용이 발생할 수 있습니다. 리전별 SKU와 쿼터를 확인하고 [Azure 가격 계산기](https://azure.microsoft.com/pricing/calculator/)로 비용을 검토합니다.

데이터베이스 방화벽의 "Azure 서비스 허용"은 본인 구독만 허용하는 기능이 아닙니다. 승인 없이 이 옵션을 켜거나 `0.0.0.0`~`255.255.255.255`를 허용해 연결 문제를 우회하지 않습니다. 네트워크 경로를 확정하지 못했으면 배포를 승인하지 않습니다.

## 완료 및 다음 단계

- [ ] Dockerfile, `azure.yaml`, Bicep과 훅을 앱의 설정 및 요구사항과 대조하고 근거를 기록했습니다.
- [ ] 관리 ID와 역할, DB 초기화 절차, 네트워크 경로와 정리 범위를 검토했습니다.
- [ ] 기록된 `azd package` 결과만 확인하고, 결과나 근거가 없으면 이미지 빌드를 미검증으로 표시했습니다.
- [ ] 발견 사항의 조치 결과와 로컬 검증 결과를 기록하고 실제 Azure 연결과 통합 테스트는 미검증으로 남겼습니다.
- [ ] 리전별 SKU, 쿼터와 비용을 검토하고 참가자가 실제 구독과 생성 범위를 승인했습니다. 네트워크 경로를 확정하고 다음 단계의 진행을 막는 문제를 해결했습니다.

위 항목을 모두 마쳤다면 [6. azd로 ACA에 배포하기](06-deploy-aca.md)로 이동합니다.
