# Azure 연결 통합 테스트

이 테스트는 기존 Azure 리소스에 **실제 데이터를 기록**합니다. 리소스 생성, DB 초기화,
배포와 자동 정리는 수행하지 않습니다. 실행 전 대상과 권한, 비용, 아래 데이터 범위를
검토하고 대화형 확인에 동의해야 합니다. CI와 비대화형 터미널에서는 실행할 수 없습니다.

## 사전 준비

- Azure CLI에 로그인한 **사용자 계정**과 해당 계정으로 선택한 구독이 필요합니다.
  서비스 주체와 관리 ID는 이 로컬 테스트에 사용할 수 없습니다. 배포된 앱의 관리 ID와는 별개입니다.
- `azd`에서 선택한 환경의 `AZURE_SUBSCRIPTION_ID`가 Azure CLI의 현재 구독과 같아야 합니다.
  스크립트는 구독을 전환하지 않습니다. 표시되는 리소스 그룹과 각 대상의 실제 소속은
  참가자가 확인해야 합니다.
- 기존 PostgreSQL Flexible Server의 Entra DB 사용자 이름이 Azure CLI 사용자 이름과 정확히
  같아야 합니다. `image_metadata` 스키마가 이미 준비되어 있어야 하며 해당 계정에 이
  테이블의 `INSERT`, `SELECT` 권한이 필요합니다. 스키마 준비는 별도의
  [DB 운영 절차](database/README.md)입니다.
- 기존 비공개 Blob 컨테이너에 로컬 사용자 계정의 `Storage Blob Data Contributor` 권한이
  필요합니다. 기존 앱 큐와 다른 **세션 사용 테스트 전용 Service Bus 큐**에 같은 계정의
  `Azure Service Bus Data Sender`, `Azure Service Bus Data Receiver` 권한이 필요합니다.
  권한은 가능한 한 해당 컨테이너와 테스트 큐 범위에 부여합니다. 앱 소비자가 테스트 큐를
  구독하지 않도록 별도로 확인하세요.
- 클라이언트에서 PostgreSQL 5432, Blob HTTPS 443, Service Bus AMQP TLS 5671과 Azure CLI
  인증 경로에 접근할 수 있어야 합니다. 방화벽·프라이빗 DNS·네트워크 설정과 JDK 신뢰
  저장소의 PostgreSQL CA를 미리 확인하세요. 스크립트는 이를 변경하지 않습니다.
- JDK 25, Azure CLI, `azd`, Maven 래퍼와 프로젝트 의존성이 필요합니다. `azure-it` 프로필은
  `maven-antrun-plugin` 3.2.0과 해당 Ant 의존성도 사용합니다. 누락된 도구를 이 스크립트가
  설치하지는 않습니다. 스크립트는 Maven을 오프라인 모드로 실행하므로 누락된 의존성은
  설치 정책을 검토한 뒤 별도로 준비하세요. 오프라인 모드는 Azure 서비스 연결을 막지 않습니다.

`azd env get-value`로 다음 비밀이 아닌 환경 값을 읽습니다. 없는 값은 확인된 실제 값으로
`azd env set`을 사용해 별도로 설정하세요. 빈 값이나 `<...>`는 사용할 수 없습니다.
공용 Azure의 정규 PostgreSQL 및 Blob 호스트만 지원합니다.

| 이름 | 값 |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Azure CLI 현재 구독 ID와 일치하는 구독 ID |
| `AZURE_RESOURCE_GROUP` | 확인할 리소스 그룹 이름 |
| `AZURE_IT_PG_HOST` | 테스트 PostgreSQL의 전체 호스트 이름 (`*.postgres.database.azure.com`) |
| `AZURE_IT_PG_DATABASE` | 기존 테스트 DB 이름 |
| `AZURE_IT_BLOB_ENDPOINT` | 테스트 스토리지의 `https://<계정>.blob.core.windows.net` |
| `AZURE_IT_BLOB_CONTAINER` | 기존 비공개 테스트 컨테이너 이름 |
| `AZURE_IT_SERVICEBUS_NAMESPACE` | 테스트 네임스페이스 이름 또는 전체 호스트 이름 |
| `AZURE_IT_SERVICEBUS_QUEUE` | 세션이 활성화된 테스트 전용 큐 이름 |
| `AZURE_IT_APP_SERVICEBUS_NAMESPACE` | 실제 앱 큐의 네임스페이스 이름 또는 전체 호스트 이름 |
| `AZURE_IT_APP_SERVICEBUS_QUEUE` | 실제 앱 큐 이름 |

`AZURE_IT_PG_USER`는 스크립트가 Azure CLI 사용자 이름으로 설정합니다. 다른 이름을 가진
DB 사용자는 지원하지 않습니다. 토큰은 `AzureCliCredential`로 메모리에서만 취득하며
환경 변수, 명령 인자 또는 파일에 저장하지 않습니다.

## 실행

다음 명령은 모두 앱 루트인 `java/`에서 실행합니다. `az account show`의 계정과 구독,
`azd env get-value AZURE_SUBSCRIPTION_ID`의 구독을 먼저 확인하세요. 스크립트는
`azd`에서 선택된 환경을 사용합니다.

Windows PowerShell 5.1 또는 PowerShell 7:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
az account show
azd env get-value AZURE_SUBSCRIPTION_ID
./scripts/run-azure-it.ps1
```

조직 정책이 실행을 제한하면 관리자에게 문의하세요. Windows PowerShell 5.1에서 직접
실행하면 공통 부트스트랩이 PowerShell 7로 위임합니다. PowerShell 7이 없으면 종료합니다.
스크립트는 자체 실행 범위에서 `../scripts/use-java.ps1 -Jdk 25`를 dot-source하고 환경을
복원합니다.

WSL/Linux Bash:

```bash
az account show
azd env get-value AZURE_SUBSCRIPTION_ID
./scripts/run-azure-it.sh
```

macOS zsh 또는 Bash에서도 앱 루트에서 같은 명령을 실행합니다.
스크립트 내부 Bash 프로세스에서 `source ../scripts/use-java.sh --jdk 25`를 실행하므로
호출자 셸의 JDK를 바꾸지 않습니다.

표시된 사용자 이름과 DB 사용자 이름, 대상, 권한, 네트워크, 비용과 변경 범위를 확인한
뒤 `RUN`을 입력하세요. 취소하려면 다른 값을 입력합니다. 승인 후 실행되는 Maven 명령은
`./mvnw -Pazure-it -pl web,worker -am verify`이며 Windows에서는 `./mvnw.cmd`를
사용합니다. 스크립트는 새 보고서 경로도 Maven에 전달합니다. 직접 Maven을 실행하면
대화형 승인 절차가 없으므로 이 실행 경로로 사용하지 마세요. 스크립트는 의존성 자동
다운로드를 막기 위해 `-o`도 추가합니다.

## 결과와 정리

스크립트가 표시하는 새 `worker/target/azure-it-reports/run.../reports`에서 세 XML 보고서와
Maven 출력을 확인하세요. 세 테스트가 각각 실행되어 성공해야 합니다. 실패, 누락 또는
건너뛰기는 실패로 처리합니다. 이전 보고서는 삭제하거나 덮어쓰지 않습니다. 보고서 경로가
다른 실행과 충돌하면 해당 실행은 실패합니다.

- PostgreSQL: Entra 토큰으로 `verify-full` TLS 연결 후 고유 ID의 행 하나를 삽입하고 조회합니다.
- Blob: 컨테이너 접근 설정이 비공개인지 확인하고 새 객체를 쓰고 인증된 SDK로 읽습니다.
  같은 객체에 대한 익명 GET은 403 또는 404여야 합니다. DB와 Blob은 SDK/JDBC 직접
  연결이며 앱의 DB 저장 경로와 웹 서버를 통한 Blob 조회는 검증하지 않습니다.
- Service Bus: 고유 세션 ID로 테스트 메시지를 보내고 그 세션만 수신합니다. 테스트가
  worker의 dev Blob 처리 코드를 호출하고 실제 수신기에 연결한 테스트 정산 어댑터를 통해
  complete를 호출한 뒤 생성된 썸네일을 읽습니다. 배포 앱의 리스너와 전체 운영 경로,
  실패 시 dead-letter, 재전달과 멱등성, 커넥션 풀의 토큰 갱신은 검증하지 않습니다.

실행 전 출력하는 DB ID, Blob 키와 메시지/세션 ID를 기록하세요. 실패한 경우 일부 항목은
생성되지 않았을 수 있고, 전송 후 실패하면 메시지가 테스트 큐에 남을 수 있습니다.
DB 행과 Blob은 자동 삭제하지 않습니다. 별도 승인 후 운영자가 출력된 정확한 DB ID로
행을 조회·확인하고 그 행만 삭제하세요. Blob도 출력된 정확한 키만 확인해 삭제하세요.
남은 메시지는 테스트 전용 큐에서 해당 세션과 메시지 ID를 확인한 후 별도로 정리하세요.
다른 행, 객체, 세션과 메시지는 변경하지 마세요.

인증·권한 오류는 표시된 사용자와 대상의 역할 및 DB 사용자를 확인하세요. 연결 오류는
DNS, 방화벽, TLS CA와 포트를 확인하세요. 큐 오류는 세션 활성화와 테스트 큐 구분을,
프로필 오류는 Maven 의존성과 `azure-it` 구성을 확인하세요. 비용은 기존 리소스의 요금제,
스토리지 용량, 요청 수와 네트워크 전송에 따라 달라지므로 실행 전 Azure 가격을 확인하세요.
