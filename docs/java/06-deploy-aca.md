# 6. azd로 ACA에 배포하기

[전체 목차](../../README.md) | [Java 목차](README.md) | [이전: azd 준비](05-prepare-azd.md) | [다음: 정리](07-cleanup.md) | [문제 해결](08-troubleshooting.md)

## 목표

검토와 승인을 마친 산출물로 참가자가 직접 리소스를 프로비저닝합니다. 이미지를 로컬에서 빌드한 뒤 배포하고 실제 기능을 확인합니다.

## 실습 범위

| 단계 | 다루는 내용 | 이 단계에서 하지 않는 작업 |
| --- | --- | --- |
| [실습 3: JDK 25로 업그레이드하기](03-upgrade.md) | Java 업그레이드, Azure 서비스 이전 코드와 배포 산출물 준비, 로컬 빌드 및 모의 테스트 | Azure 리소스 생성, 실제 Azure 연결, 앱 배포 |
| [실습 4: Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md) | 이전된 Azure 서비스 코드와 테스트 검토, 필요한 수정과 로컬 검증 | Azure 리소스 생성과 실제 연결 |
| [실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md) | Dockerfile, `azure.yaml`, Bicep, DB 초기화 절차와 배포 설정 검토 및 수정 | 프로비저닝, DB 초기화, 이미지 게시, 배포 |
| 실습 6: azd로 ACA에 배포하기 (이 문서) | 승인 후 Azure 리소스 프로비저닝, DB 초기화, 로컬 이미지 빌드, 배포와 실제 기능 확인 | 승인하지 않은 리소스나 데이터 변경 |

## 실습 전 확인 사항

[실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 산출물을 검토하고 승인한 뒤, 같은 Copilot app 터미널의 **앱 루트**를 사용합니다.

이 문서의 `../scripts/` 도우미는 앱 루트에서 직접 실행합니다. Windows PowerShell 5.1에서는 PowerShell 7로 실행을 위임합니다. 방화벽이나 DB를 변경하는 도우미는 대상 정보를 표시하고 `APPLY` 입력으로 승인을 받습니다. CI나 비대화형 환경에서는 변경 작업을 실행하지 않습니다. 오류가 나면 다음 단계로 넘어가지 마세요.

로컬 이미지 빌드를 위해 Docker Engine을 실행하고 `docker info`로 연결을 확인합니다.

> [!NOTE]
> 다른 컨테이너 빌드 엔진을 사용하려면 [8. 문제 해결: 대체 엔진 설정](08-troubleshooting.md#대체-엔진-설정)을 참고합니다.

DB 초기화에 사용할 PostgreSQL 클라이언트도 확인합니다. 명령을 찾을 수 없다면 [준비: PostgreSQL 클라이언트 설치](00-setup.md#postgresql-클라이언트-설치)에 따라 설치하거나 실행 경로를 설정한 뒤 진행합니다.

```bash
psql --version
```

## 환경 설정

현재 셸에서 Docker Engine을 사용하도록 설정합니다. 설치된 azd가 지원하면 터미널 환경을 자동으로 비대화형으로 판단하는 기능도 해제합니다.

```bash
export AZD_CONTAINER_RUNTIME=docker
export AZD_NON_INTERACTIVE=false
```

```powershell
# PowerShell
$env:AZD_CONTAINER_RUNTIME = 'docker'
$env:AZD_NON_INTERACTIVE = 'false'
```

> [!NOTE]
> Podman을 사용하려면 위 `AZD_CONTAINER_RUNTIME` 값을 `podman`으로 바꾸고 앞서 안내한 대체 엔진의 실행 조건을 확인합니다.

Azure CLI와 azd의 로그인은 별개입니다. 필요한 경우 참가자가 직접 로그인하고, 로그인 상태와 선택한 구독을 확인합니다.

```bash
az login
azd auth login
az account show --query "{name:name,id:id}" --output table
azd auth login --check-status
```

앱 배포 환경을 만듭니다. `<...>`를 실제 값으로 바꿉니다(예: `contoso-asset-manager`).

```bash
azd env new "<개인별-고유-환경명>"
```

## 프로비저닝, 패키징, 배포

각 명령이 성공했는지 확인하고 결과를 검토한 뒤 다음 명령을 실행합니다. 명령 블록 전체를 무인 실행하지 않습니다.

> [!NOTE]
> `azd up`은 프로비저닝, 패키징, 배포를 묶어 실행합니다. 이번 실습에서는 실패한 단계와 승인 범위를 알 수 있도록 각 명령을 따로 실행합니다.

### 리소스 프로비저닝

[실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 검토한 훅, 구독, 리전, SKU, 권한, 네트워크와 비용을 확인하고 승인합니다. 환경에 구독과 리전이 이미 설정되어 있다면 다음 명령으로 확인합니다. 구독은 앞서 실행한 `az account show`의 결과와 대조합니다. azd는 이미 설정된 값을 다시 묻지 않을 수 있습니다.

```bash
azd env get-value AZURE_SUBSCRIPTION_ID
azd env get-value AZURE_LOCATION
```

값이 설정되지 않았다면 프로비저닝 중 선택을 요청할 수 있습니다. 선택 질문이 반드시 나오는 것은 아닙니다. 승인한 대상이 불분명하면 진행하지 않습니다.

```bash
azd provision
```

> [!NOTE]
> 프로비저닝에 실패하면 비밀정보를 제거한 오류 메시지를 Copilot app 채팅에 전달하고 원인 분석과 해결을 요청합니다. 변경 범위와 영향을 확인하고 승인한 뒤 조치하고, 프로비저닝에 성공하면 다음 단계로 진행합니다.

### 리소스 확인

리소스 프로비저닝에 성공했다면 앱 루트에서 리소스 그룹 이름을 읽어 리소스 목록을 확인합니다.

```bash
rg=$(azd env get-value AZURE_RESOURCE_GROUP)
az resource list --resource-group "$rg" --query "[].{name:name,type:type}" --output table
```

```powershell
# PowerShell
$rg = azd env get-value AZURE_RESOURCE_GROUP
az resource list --resource-group $rg --query "[].{name:name,type:type}" --output table
```

목록을 [실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 승인한 리소스와 대조합니다. 프로비저닝이 실패했거나 이름이 비어 있거나 필요한 리소스가 없으면 원인을 해결한 뒤 진행합니다.

### DB 방화벽에 클라이언트 IP 등록

공개 네트워크로 PostgreSQL에 연결하려면 DB 초기화 전에 **접속할 PC의 공인 IPv4 주소**를 서버 방화벽에 등록합니다. `192.168.x.x` 같은 사설 IP나 DB 서버의 IP가 아니라, DB 서버에서 보이는 접속자의 공인 IP여야 합니다. 사설 네트워크를 사용한다면 공개 접근을 켜지 말고 승인한 사설 연결 경로를 확인합니다.

클라이언트 IP는 Azure Portal과 스크립트 중 한 가지 방법으로 등록합니다.

#### Azure Portal에서 등록

Azure Portal에서 대상 PostgreSQL 서버의 **네트워킹**을 열고 **현재 클라이언트 IP 추가**를 선택합니다. 표시된 주소를 확인한 뒤 변경 사항을 저장합니다. VPN이나 회사 프록시를 사용하면 브라우저와 DB 접속의 공인 IP가 다를 수 있습니다. 확실하지 않으면 네트워크 관리자에게 확인하세요. 외부 IP 조회 서비스를 따로 사용할 필요는 없습니다.

> [!NOTE]
> 공개 네트워크로 연결하는 경우, PostgreSQL 서버의 **네트워킹**에서 **Allow public access from any Azure service within Azure to this server** 옵션도 확인합니다. 이 옵션은 해당 ACA 환경이나 본인 구독뿐 아니라 다른 구독의 Azure 서비스에도 네트워크 접근을 허용합니다. 이번 실습에서 이 범위를 허용하기로 승인했다면 옵션을 체크하고 저장합니다. DB 인증과 권한 설정은 별도로 필요합니다.

#### 스크립트로 등록

`<확인한-공인-IPv4>`를 실제 주소로 바꾸고 도우미를 실행합니다. 표시된 서버와 IP 주소를 확인한 뒤 승인합니다. 방화벽 규칙을 조회하고 변경할 권한이 필요합니다. 도우미는 IP 하나만 등록하며 기존 규칙을 삭제하거나 허용 범위를 덮어쓰지 않습니다. Azure 서비스 전체나 모든 IP를 허용하는 규칙도 만들지 않습니다.

```bash
# zsh/bash
clientIp="<확인한-공인-IPv4>"
../scripts/register-java-db-client-ip.sh --client-ip "$clientIp"
```

```powershell
# PowerShell
$clientIp = "<확인한-공인-IPv4>"
../scripts/register-java-db-client-ip.ps1 -ClientIp $clientIp
```

> [!NOTE]
> 터미널에서 [ipify](https://www.ipify.org)의 API로 공인 IPv4 주소를 확인할 수도 있습니다. **Microsoft나 Azure가 운영하지 않는 외부 서비스**이며, 조회 시 공인 IP와 요청 정보가 해당 서비스에 전달됩니다. 조직의 외부 서비스 사용 정책을 확인한 뒤 필요한 경우에만 사용하세요.
>
> ```bash
> clientIp=$(curl -4 --fail --silent --show-error --max-time 10 https://api.ipify.org)
> ```
>
> ```powershell
> # PowerShell
> $clientIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
> ```
>
> 조회 결과가 실제 DB 접속의 송신 IP와 같은지 확인한 뒤 위 `$clientIp` 값에 입력합니다. VPN이나 프록시 환경에서는 다를 수 있으므로 결과를 확인 없이 자동 등록하지 마세요.

> [!NOTE]
>
> 공개 네트워크 접근이 활성화된 서버에서는 [Azure CLI로도 Azure 서비스 접근을 허용](https://learn.microsoft.com/en-us/cli/azure/postgres/flexible-server/firewall-rule#az-postgres-flexible-server-firewall-rule-create)할 수 있습니다.
>
> **다른 구독의 Azure 서비스에도 네트워크 접근을 허용하는 범위**를 확인하고 승인한 경우에만 실행합니다.
>
> ```bash
> # zsh/bash
> rg=$(azd env get-value AZURE_RESOURCE_GROUP)
> pgServer=$(azd env get-value POSTGRESQL_SERVER)
> address="0.0.0.0"
> az postgres flexible-server firewall-rule create --resource-group $rg --server-name $pgServer --name AllowAzureServices --start-ip-address $address --end-ip-address $address
> ```
>
> ```powershell
> # PowerShell
> $rg = azd env get-value AZURE_RESOURCE_GROUP
> $pgServer= azd env get-value POSTGRESQL_SERVER
> $address = "0.0.0.0"
> az postgres flexible-server firewall-rule create --resource-group $rg --server-name $pgServer --name AllowAzureServices --start-ip-address $address --end-ip-address $address
> ```
>
> 시작과 끝 IP가 모두 `0.0.0.0`인 규칙은 Azure 내부 연결을 허용하는 특수 규칙입니다. 모든 인터넷 IP를 허용하는 규칙은 아니며, DB 인증과 권한 설정은 여전히 필요합니다.

#### 등록 결과 확인

규칙의 시작과 끝 IP가 같고 승인한 주소만 허용했는지 확인합니다. 적용까지 몇 분 걸릴 수 있습니다. 계속 연결 시간이 초과되면 PC가 연결된 네트워크에서 외부로 나가는 TCP 5432 포트를 차단하는지도 확인합니다. 방화벽에서 연결을 허용해도 DB 인증과 권한 설정은 별도로 필요합니다.

공인 IP가 바뀌면 새 주소를 확인해 등록하고, 기존 규칙은 별도 승인 후 삭제합니다. 위 규칙은 해당 PC에만 적용되므로 ACA의 DB 연결도 별도로 허용해야 합니다. ACA 수신 IP를 송신 IP로 등록하지 마세요.

### DB 연결용 루트 인증서 준비

`psql`은 서버 인증서와 호스트 이름을 검증합니다. DB에 연결할 셸에서 도우미를 실행해 [Azure PostgreSQL이 사용하는 루트 CA](https://learn.microsoft.com/en-us/azure/postgresql/security/security-tls#root-cas-used-by-azure-database-for-postgresql)를 내려받습니다. 도우미가 출력한 PEM 파일 경로를 `PGSSLROOTCERT`에 지정합니다. Bash 도우미에는 `curl`과 `openssl`이 필요합니다. 시스템 인증서 저장소는 변경하지 않습니다.

```bash
# zsh/bash
PGSSLROOTCERT=$(../scripts/prepare-java-db-root-cert.sh) && export PGSSLROOTCERT
```

```powershell
# PowerShell
$env:PGSSLROOTCERT = & ../scripts/prepare-java-db-root-cert.ps1
if ($LASTEXITCODE -ne 0) { throw "Root CA preparation failed." }
```

다른 터미널에서 DB에 연결하거나 임시 파일이 삭제됐다면 다시 실행합니다.

### DB 초기화

[실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 검토한 DB 초기화 안내와 SQL을 사용합니다. 승인한 새 데모 DB만 대상으로 하며, 대상이나 권한이 불분명하면 중단합니다.

**로컬 PC의 Azure CLI에 로그인한 Entra 관리자로 DB 사용자와 테이블을 생성하고 권한을 부여**합니다. 앱은 web/worker 관리 ID로 연결합니다. 현재 PC에서 DB에 접근할 수 있고 현재 셸에 `PGSSLROOTCERT`가 설정되어 있어야 합니다.

앱 루트에서 아래 도우미를 실행합니다. 기본 SQL 경로는 `infra/db/bootstrap-identities.sql`과 `infra/db/initialize-image-metadata.sql`입니다. 경로가 다르면 Bash의 `--sql-path`, PowerShell의 `-SqlPath`로 지정합니다.

초기화 전에 서버, 관리자, web/worker 관리 ID 이름과 DB 이름을 조회해 승인한 대상과 대조합니다. 앱마다 사용자 할당 관리 ID가 정확히 하나여야 하며 조회에 실패하거나 값이 비어 있으면 중단합니다.

```bash
# zsh/bash
../scripts/get-java-db-info.sh
```

```powershell
# PowerShell
../scripts/get-java-db-info.ps1
```

#### 1. DB 사용자와 기본 권한 설정

`postgres` DB에 Entra 관리자로 연결해 검토한 SQL을 실행합니다. SQL은 web/worker 보안 주체를 생성하고 DB 연결 권한을 부여합니다. 이후 앱 DB에 연결해 스키마 사용 권한을 설정해야 합니다. 실행이 끝나면 도우미가 두 역할에 `CONNECT`와 `USAGE`가 허용되고 스키마 `CREATE`는 금지됐는지 유효 권한을 확인합니다.

```bash
# zsh/bash
../scripts/initialize-java-db-users.sh
```

```powershell
# PowerShell
../scripts/initialize-java-db-users.ps1
```

#### 2. 테이블 생성과 앱 권한 설정

같은 Entra 관리자 계정으로 앱 DB에 연결해 테이블과 앱 권한을 설정합니다. 관리자 단계만 끝낸 경우에도 이 단계는 필요합니다. 실행 후 도우미가 테이블 소유자와 web/worker의 유효 권한을 확인합니다.

```bash
# zsh/bash
../scripts/initialize-java-db-schema.sh
```

```powershell
# PowerShell
../scripts/initialize-java-db-schema.ps1
```

#### 초기화 결과 확인

두 초기화 도우미는 [권한 검증 SQL](../../scripts/java-db-permissions.sql)을 자동으로 실행하므로 별도 쿼리를 입력할 필요는 없습니다. 각 도우미 실행 끝에 `[PASS] SQL and effective permission checks completed.`로 시작하는 메시지가 나오는지 확인합니다.

출력에서 테이블 소유자가 초기화한 관리자이고, web은 조회, 추가, 수정, 삭제를, worker는 조회와 수정만 할 수 있는지 확인합니다. 두 앱 역할에는 스키마 생성이나 테이블 변경 권한이 없어야 합니다.

실패하면 일부 변경이 적용됐을 수 있으므로 DB 상태와 원인을 확인합니다. 초기화와 권한 검증을 완료하고 승인한 범위와 일치하는지 확인한 뒤 배포합니다. 앱 관리 ID의 인증과 실제 연결은 배포 후 확인합니다.

### 이미지 패키징

앱 루트에서 web과 worker의 배포용 컨테이너 이미지를 Docker Engine으로 빌드합니다.

```bash
azd package
```

빌드 로그에서 Docker Engine 사용 여부, `linux/amd64` 플랫폼, Java 25 이미지와 web/worker 각각의 빌드 결과를 확인합니다. 빌드에 실패했거나 결과를 확인하지 못했다면 원인을 해결하고 성공 여부를 확인한 뒤 배포합니다.

### 배포

앱 루트에서 web과 worker 이미지를 게시하고 Azure Container Apps에 배포합니다.

```bash
azd deploy
```

`azd deploy`는 이미지를 다시 빌드할 수 있습니다. 패키징 후 소스를 바꾸지 않고 실제 배포된 이미지의 태그와 다이제스트를 기록합니다. 이미지 게시와 앱 업데이트가 성공했는지 확인한 뒤 결과를 조회합니다.

```bash
azd show
```

## 리소스 상태와 기능 확인

Azure 포털에서 앞서 확인한 리소스 그룹을 열고 web과 worker Container App을 각각 확인합니다.

1. **개요**와 **수정 버전 관리(Revision management)** 에서 배포 상태와 이번에 배포한 수정 버전의 준비 상태, web의 URL을 확인합니다.
2. **설정 → 수신(Ingress)** 에서 web과 worker의 수신 설정이 [실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 검토한 구성과 일치하는지 확인합니다.
3. worker의 **모니터링 → 로그 스트림(Log stream) → 콘솔(Console)** 에서 처리 로그와 오류를 확인합니다. 수정 버전, 복제본 또는 컨테이너가 여러 개라면 해당 대상을 선택합니다.

터미널에서는 아래 도우미로 두 앱의 최신 수정 버전이 준비 완료 상태인지, 활성화되어 정상 동작하는지 확인합니다. web은 외부 ingress와 8080 포트를 사용하고 worker는 ingress가 꺼져 있는지도 확인합니다. 각 앱의 최근 시스템 로그 20줄과 web의 HTTP 응답도 조회합니다. 필요한 azd 출력이 없거나 검사에 실패하면 오류로 종료합니다.

```bash
# zsh/bash
../scripts/check-java-deployment.sh
```

```powershell
# PowerShell
../scripts/check-java-deployment.ps1
```

이 결과만으로 DB 연결이나 업로드부터 worker 처리까지의 성공을 보장할 수는 없습니다. 실제 배포된 이미지의 식별자를 확인하고 아래 통합 및 end-to-end 테스트를 별도로 진행합니다.

### Azure 통합 테스트 실행

[실습 4: Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md#azure-통합-테스트-준비)에서 준비한 테스트는 실제 Azure의 DB, Service Bus와 Blob에 연결해 데이터를 읽고 씁니다. 로컬 실행 계정의 권한을 사용하므로 이 결과만으로 web이나 worker의 관리 ID 인증까지 확인할 수는 없습니다.

1. [실습 4: Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md#azure-통합-테스트-준비)에서 생성한 테스트, `azure-it` 프로필, 실행 스크립트와 안내를 검토합니다. 테스트나 스크립트가 없거나 실행 설정이 불분명하면 해당 실습을 보완한 뒤 진행합니다.
2. 테스트 대상과 실행 계정을 [실습 5: azd 배포 산출물 준비하기](05-prepare-azd.md)에서 검토한 출력 및 DB 초기화 안내와 대조합니다. Azure CLI 사용자에게 DB, Blob과 테스트 전용 큐에 필요한 최소한의 데이터 접근 권한이 있는지 확인합니다. 네트워크 경로와 PostgreSQL TLS 인증서의 신뢰 여부도 확인합니다. 앱 큐 출력이 실제 배포 설정과 일치하는지 살펴보고, 앱 큐와 다른 테스트 전용 큐만 사용합니다.

   Azure CLI 사용자 이름이 해당 PostgreSQL DB 사용자 이름과 다르거나 대상, 권한, 비용 또는 데이터 변경 범위가 불분명하면 실행하지 않습니다. 리소스나 권한이 없으면 필요한 범위와 비용을 검토하고 별도 승인을 받습니다. 로그인 상태가 없거나 주체가 다르면 `az login`으로 승인된 사용자 계정에 로그인한 뒤 확인합니다. 서비스 주체의 DB 역할 이름은 추측하지 않습니다.
3. 앱 루트에서 현재 셸에 맞는 스크립트를 직접 실행합니다. 스크립트가 JDK 25를 선택하고 Azure CLI와 azd에서 대상을 조회합니다. 표시된 구독, 리소스, 사용자와 데이터를 읽고 쓰는 범위를 확인합니다. 앞서 검토한 비용도 확인한 뒤 실행에 명시적으로 동의합니다. CI나 비대화형 환경에서는 실행할 수 없습니다.

   ```bash
   # zsh/bash
   ./scripts/run-azure-it.sh
   ```

   ```powershell
   # PowerShell
   ./scripts/run-azure-it.ps1
   ```

4. 종료 코드와 이번 실행의 테스트 보고서에서 DB, Service Bus와 Blob 테스트가 각각 실행되고 성공했는지 확인합니다. 프로필이 없거나 테스트가 실행되지 않았거나 건너뛴 경우는 성공이 아닙니다. 실패 또는 미검증 항목과 생성된 테스트 데이터의 식별자를 기록합니다. 데이터 정리는 범위와 영향을 확인하고 별도로 승인합니다.

### End-to-end 테스트 작성과 실행

배포된 앱에서 사용자의 업로드부터 결과 조회까지 확인하는 end-to-end 테스트를 준비합니다. 앱 루트에서 Copilot app 채팅에 다음을 요청합니다.

```text
현재 앱의 화면, 업로드 및 조회 흐름, 테스트 도구와 배포 설정을 읽고 배포된 web을 대상으로 하는 end-to-end 테스트를 작성해 줘.
기존 테스트 도구를 우선 사용하고 테스트 코드와 실행 안내만 준비해 줘. 앱 운영 코드, 배포 설정과 이미지는 변경하지 말고 실제 앱 접속이나 테스트 실행도 하지 마.

- 개인 정보가 없는 테스트 이미지를 업로드하고, 해당 이미지를 식별해 처리 완료와 결과 조회까지 검증해 줘.
- 실제 앱과 검토한 배포 구성을 바탕으로 DB 메타데이터, 비공개 Blob, Service Bus와 worker 처리 결과의 확인 방법 및 성공 조건을 제시해 줘. 원본 `dev` 프로필에 없던 DB 기록은 `dev` 외 S3 경로에서 이전한 동작으로 구분해 줘.
- 비동기 처리의 확인에는 제한 시간과 실패 조건을 정해 줘. HTTP 200이나 건너뛴 검사만으로 전체 성공을 표시하지 마.
- 비공개 Blob의 익명 접근이 거부되는지 확인하되, 권한 있는 조회와 구분해 줘. 오류나 연결 실패를 접근 제어 성공으로 처리하지 마.
- 테스트별 고유 식별자를 사용하고 기존 데이터나 메시지를 수정하거나 삭제하지 마. 자동 정리는 하지 말고 테스트 데이터와 별도 정리 방법을 안내해 줘.
- 실행 대상 URL, 실행 계정, 필요한 권한, 네트워크, 데이터를 읽고 쓰는 범위, 비용과 필수 설정을 명시해 줘. 대상이 없거나 확인할 수 없으면 실패하거나 미검증으로 표시해 줘.
- 앱 루트에서 Windows PowerShell과 WSL/Linux의 Bash 및 macOS의 zsh/bash 각각으로 실행할 정확한 준비 및 실행 명령, 결과 확인과 실패 시 조치를 제시해 줘. 값이 없는 대상은 임의로 채우지 마.
- 비밀정보와 서명된 URL을 코드, 명령 인자, 로그나 Git에 넣지 마. 의존성이나 브라우저 설치가 필요하면 설치하지 말고 필요한 항목을 보고해 줘.
- 실제 Azure 연결, 데이터 변경, 배포, 테스트 실행과 도구 설치는 하지 마. 변경 파일과 검증하지 못한 항목을 보고해 줘.
```

생성된 코드와 안내에서 앱 동작 흐름, 대상과 권한, 데이터 범위와 성공 조건을 확인합니다. 도구 설치는 별도로 결정합니다. 승인된 환경에서 구독, web URL, 실행 계정, 비용과 데이터 변경 범위를 확인하고 실행을 승인합니다. 이후 현재 셸에 맞는 준비 및 실행 명령을 직접 실행합니다. 확인하지 못한 항목은 미검증으로 기록하고 테스트 데이터는 별도 승인 후 정리합니다.

### 결과 검토

로그 해석이 필요하면 Copilot app 채팅에 비밀정보를 제거한 결과와 다음 요청을 전달합니다.

```text
전달한 azd 출력, 리소스 상태와 통합 및 end-to-end 테스트 결과를 검토해 줘. 구독이나 환경을 바꾸지 마.
web/worker 이미지의 태그와 다이제스트, JDK 25, 준비 상태와 수신 설정의 근거를 확인해 줘.
DB TLS/관리 ID와 실제 권한, Service Bus 처리, Blob 비공개 검증의 누락을 찾아 줘.
실제 실행 결과와 미실행 항목을 구분하고 추가 검사 명령은 제시만 해 줘.
운영 데이터 삭제, 방화벽 전체 개방, RBAC 범위 확대는 하지 마.
오류가 있으면 비밀정보를 제거한 로그와 원인을 제시하고 필요한 변경 승인을 기다려 줘.
```

Java 명령 실행을 추가로 요청할 때는 앱 루트의 같은 셸에서 JDK 25를 먼저 선택하도록 안내합니다. Windows에서는 `. ../scripts/use-java.ps1 -Jdk 25`, macOS와 Linux에서는 `source ../scripts/use-java.sh --jdk 25`를 사용합니다. 코드 수정이 필요하면 수정 범위와 복구 계획을 검토한 뒤 진행합니다.

수동 확인이 필요하면 `azd show`의 **web URL**을 브라우저에서 열고 [실습 1: 원본 앱을 로컬에서 실행하기](01-run-locally.md)와 같은 개인 정보 없는 입력을 사용합니다. DB 메타데이터 기록과 조회, Blob 저장과 조회, Service Bus 수신과 worker 처리가 연결되는지 확인합니다. DB 메타데이터는 원본 `dev`에 없던 동작이므로 `dev` 외 S3 구현에서 이전한 기능으로 구분해 기록합니다. 비공개 Blob URL의 익명 요청으로 파일이 공개되지 않는지도 확인합니다.

단위 테스트 통과나 HTTP 200만으로는 완료가 아닙니다. 컨테이너의 로컬 파일에 의존하지 않고 새 수정 버전에서도 업로드한 파일을 조회할 수 있는지 확인합니다. 앱을 강제 종료하는 대신 정상 재배포하거나 새 수정 버전을 배포해 검증합니다. 이때 추가 비용도 확인합니다.

## 완료 및 다음 단계

- [ ] 승인한 리소스와 web/worker의 정상 수정 버전을 확인하고 이미지 식별자와 배포 결과를 기록했습니다.
- [ ] Azure 통합 테스트와 end-to-end 테스트 결과로 실제 사용자 기능을 확인하고 미검증 항목을 구분해 기록했습니다.
- [ ] 로컬 파일에 의존하지 않고 새 수정 버전에서도 업로드를 조회할 수 있는지 확인했습니다.

위 항목을 모두 마쳤다면 [7. 리소스와 로컬 실행 정리하기](07-cleanup.md)로 이동합니다.
