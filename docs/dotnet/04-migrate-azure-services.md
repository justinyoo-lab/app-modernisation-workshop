# .NET 4. Azure 서비스로 이전하고 Windows 의존성 제거하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: 업그레이드](03-upgrade.md) | [다음: azd 준비](05-prepare-azd.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

.NET 10 업그레이드 결과와 남은 의존성을 확인한 뒤, 같은 **앱 루트**의 Copilot app PowerShell 7 터미널에서 Modernize CLI를 사용합니다. 이 단계에서는 Azure 리소스를 아직 만들지 않습니다.

## 이전 계획과 실행

다음 입력을 앱 루트의 `ws04-azure-code-input.txt`에 UTF-8로 저장하고 실제 평가/업그레이드 결과 경로를 추가합니다.

```text
.github/skills/dotnet-aca-workshop/SKILL.md와 실제 .NET 10 업그레이드 결과를 읽고
Azure 서비스 이전 코드와 테스트만 계획해 줘. 지금은 실행하지 마.
기존 사용자 동작과 .NET 10을 유지하고 최종 Linux 실행을 준비해 줘.

- LocalDB를 Azure SQL로 바꾸고 Microsoft.Data.SqlClient/EF Core의
  관리 ID/Entra 인증, TLS와 연결 복구 정책을 현재 버전 기준으로 구성한다.
- MSMQ/System.Messaging 및 임시 Windows 어댑터를 Service Bus SDK로 대체한다.
  메시지 포맷, 송수신, 성공 후 complete, 실패 재시도/dead-letter,
  중복 처리의 멱등성과 종료 시 정리를 포함한다.
- 소비자가 같은 웹 프로세스에 있다면 BackgroundService 수명 주기를 명확히 한다.
- 로컬 파일을 private Blob으로 옮기고 기존 화면의 업로드/조회 경로를 연결한다.
  웹 컨테이너 로컬 디스크나 wwwroot를 영구 저장소로 사용하지 않는다.
- Data Protection 키를 private Blob 등에 보존하고 앱 이름/저장 경로를 고정해
  revision 변경으로 쿠키/위조 방지 토큰 처리가 깨지지 않도록 한다.
- 기본 인증 체인의 로컬 개발자 ID와 ACA 관리 ID를 구분하고 비밀을 Git에 넣지 않는다.
- EnsureDeleted/데이터베이스 재생성과 자동 파괴적 seed를 제거한다.
  새 데모 DB의 migration/seed는 명시적으로 승인한 별도 절차로 만든다.
- System.Web, LocalDB, MSMQ, 레지스트리, 드라이브 문자와 Windows 전용 API의
  잔존 여부를 조사하고 Linux 최종 경로에서 제거한다.
- DB 내부 사용자와 역할, 스키마 준비, Azure 데이터 역할과 환경 변수를 문서화한다.
- 단위 검사와 외부 Azure가 필요한 통합 검사를 분리하고 필요한 테스트를 추가한다.

코드/테스트만 작업 목록에 넣고 리소스 생성, 실제 DB 변경/데이터 이전,
이미지 게시와 배포는 제외해 줘. 실제 검증과 미실행 통합 항목을 구분해 줘.
```

```powershell
$goal = Get-Content ./ws04-azure-code-input.txt -Raw -Encoding utf8
modernize plan create $goal --source . --language dotnet --plan-name ws04-azure-code
```

실제 `plan.md`와 `tasks.json`을 함께 읽고 코드/단위 검사 범위를 승인합니다. 무관한 작업 트리 변경과 비밀이 없는지 확인한 뒤 실행 전 커밋을 기록합니다.

```powershell
git status --short
$before = git rev-parse HEAD
modernize plan execute "승인한 ws04-azure-code와 워크숍 스킬의 코드/테스트만 실행해 줘. Windows 의존성 제거와 Data Protection을 포함하고 Azure/DB 변경과 배포는 하지 마. 미실행 통합 검사를 구분해 줘." --source . --language dotnet --plan-name ws04-azure-code --delegate local
```

## 권한과 데이터 검토

Azure SQL에 리소스 역할을 부여하는 것만으로 SQL 접속 권한이 생기지 않습니다. Entra 관리자, 앱 관리 ID의 DB 사용자 생성, 필요한 테이블/프로시저 권한과 migration 실행 주체를 구분합니다. 사용자를 만드는 SQL 절차에서 디렉터리 조회 권한이 필요한지도 확인합니다. 이를 해결하려고 무조건 구독 Owner 또는 디렉터리 전체 권한을 부여하지 않습니다.

Service Bus 송신/수신 역할과 Blob 데이터 역할은 실제 책임과 범위에 맞게 부여합니다. 관리 ID에 Contributor만 주고 데이터 접근이 된다고 가정하지 않습니다. Data Protection 키는 일반 업로드와 경로를 분리하고 키를 담은 Blob을 공개하지 않습니다.

**앱 루트의 Windows PowerShell 7**에서 실제 솔루션 경로로 실행합니다.

```powershell
dotnet restore "<실제-솔루션-경로>"
dotnet build "<실제-솔루션-경로>" --no-restore
dotnet test "<실제-솔루션-경로>" --no-build
git status --short
git log --oneline "$before..HEAD"
git diff --stat "$before..HEAD"
git diff "$before..HEAD"
git diff
git diff --cached
```

명령별 종료 코드와 실제 테스트 수를 확인하고 실패하면 멈춥니다. 자동 커밋에 앱 외부 파일, 생성물과 비밀이 포함되지 않았는지도 검토합니다.

아직 Azure 리소스가 없으므로 클라우드 통합 검사 통과를 주장하지 않습니다. 실제 Azure 리소스를 요구하는 로컬 실행은 실습 6의 프로비저닝/DB 초기화 후 수행할 수 있습니다.

## 완료 기준과 문제 해결

MSMQ가 SDK 패키지 이름만 바뀐 채 남아 있지 않고, SQL/Service Bus/Blob/Data Protection 경로와 환경 설정이 연결되어야 합니다. 단위 검사와 DB 초기화 절차가 있고 미실행 통합 항목이 명확해야 합니다. Linux 컨테이너 빌드와 실제 서비스 연결은 실습 6에서 확인합니다. [문제 해결](08-troubleshooting.md)에서 인증과 Linux 의존성 항목을 참고하세요.
