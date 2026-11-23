# .NET 3. Modernize CLI로 .NET 10 전환하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: 평가와 계획](02-assess-and-plan.md) | [다음: Azure 서비스 이전](04-migrate-azure-services.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

Copilot app의 **Windows PowerShell 7 터미널**, 같은 **앱 루트**에서 진행합니다. 원본 IIS Express는 먼저 중지합니다. 실제 평가/계획 파일과 기준선 코드가 같은 사본에 있는지 확인합니다.

Modernize CLI는 작업별 커밋을 만들 수 있습니다. 각 실행 직전 `git status --short`를 확인하고 무관한 변경과 비밀이 없는 상태에서 기준 커밋을 기록합니다. 미커밋 작업은 먼저 별도로 보존합니다.

## 원본 기준 테스트

실습 2에서 검토한 `ws03-baseline`만 실행합니다. DB 초기화가 필요한 테스트는 실습 전용 대상과 영향을 별도로 승인합니다.

```powershell
git status --short
$before = git rev-parse HEAD
modernize plan execute "승인한 ws03-baseline과 .github/skills/dotnet-aca-workshop/SKILL.md를 따라 원본 v4.8의 기준 테스트만 보강하고 실행해 줘. Framework MSBuild와 기존 도우미를 사용하고 테스트를 삭제하거나 건너뛰지 마. 업그레이드, Azure 변경과 배포는 하지 마." --source . --language dotnet --plan-name ws03-baseline --delegate local
```

아래 [실행 결과 검토](#실행-결과-검토)로 자동 커밋과 미커밋 변경을 함께 확인합니다. 원본 테스트, LocalDB/MSMQ의 실행 조건과 사람이 확인한 UI 결과가 구분되어야 다음 계획을 만듭니다.

## 업그레이드 계획 생성과 검토

다음 요구사항을 앱 루트의 `ws03-upgrade-input.txt`에 UTF-8로 저장하고 실제 평가 보고서 경로를 첫 줄에 추가합니다.

```text
.github/skills/dotnet-aca-workshop/SKILL.md, 평가와 기준 테스트 결과를 읽고
Contoso University를 .NET Framework v4.8/MVC 5에서 .NET 10/ASP.NET Core로
업그레이드하는 계획만 작성해 줘. 지금은 실행하지 마.
기존 Razor, 라우팅, 유효성 검사, CRUD/검색/페이지 이동, 큐/파일 기능을 유지해 줘.
SDK 스타일 프로젝트, ASP.NET Core 시작/DI/미들웨어, 설정, 정적 파일,
EF Core와 NuGet 변경을 포함하고 EF Core 3.1의 쿼리 번역/스키마 차이를 검토해 줘.
global.json은 설치한 정식 .NET 10 SDK와 맞추고 net10.0을 사용해 줘.
더 새 SDK가 있어도 .NET 11로 올리지 마.
MSMQ가 Linux에서 바로 동작한다고 가정하지 마. 임시 Windows 어댑터가 필요하면
범위, 미완료 기능과 다음 단계의 제거 조건을 명시하고 테스트를 지우지 마.
복원/빌드/테스트와 Windows 로컬 기능 확인, 실제 프로젝트 경로,
launch profile/URL, 중단/복구 기준을 포함해 줘.
Azure 이전, 리소스 생성, DB 변경/데이터 이전과 컨테이너 배포는 포함하지 마.
```

```powershell
$goal = Get-Content ./ws03-upgrade-input.txt -Raw -Encoding utf8
modernize plan create $goal --source . --language dotnet --plan-name ws03-upgrade
```

생성된 `plan.md`와 `tasks.json`을 함께 읽고 버전, 파일 범위와 검증 기준을 승인합니다. 미승인 설치나 Azure 작업이 포함되면 수정한 뒤 다시 검토합니다.

## 승인한 업그레이드 실행

```powershell
git status --short
$before = git rev-parse HEAD
modernize plan execute "승인한 ws03-upgrade와 워크숍 스킬의 .NET 10 업그레이드만 실행해 줘. 기준 테스트를 생략하지 말고 임시 Windows 의존성을 보고해 줘. Azure 변경과 배포는 하지 마." --source . --language dotnet --plan-name ws03-upgrade --delegate local
```

명령이 실패하면 중단하고 오류와 미완료 작업을 기록합니다. 실제 생성된 솔루션과 프로젝트 경로로 아래 값을 바꿉니다. `.slnx`로 바뀌었다면 그 경로를 사용합니다. 각 명령 직후 `$LASTEXITCODE`를 확인하며 실패 시 다음 명령으로 진행하지 않습니다.

```powershell
dotnet --version
dotnet restore "<실제-솔루션-경로>"
dotnet build "<실제-솔루션-경로>" --no-restore
dotnet test "<실제-솔루션-경로>" --no-build
dotnet run --project "<실제-웹-프로젝트-경로>"
```

테스트가 0개라면 성공 종료 코드도 회귀 확인이 아닙니다. 발견/실행한 테스트 수와 누락된 기능을 기록합니다. 별도 터미널의 앱 실행 URL에서 원본 학생/강좌/강사/학과/통계와 큐/파일 동작을 비교합니다.

## 실행 결과 검토

각 실행 직전 기록한 기준 커밋으로 자동 커밋과 미커밋 변경을 함께 검토합니다.

```powershell
git status --short
git log --oneline "$before..HEAD"
git diff --stat "$before..HEAD"
git diff "$before..HEAD"
git diff
git diff --cached
```

`git diff`가 비어 있어도 자동 커밋을 확인합니다. 앱 밖의 파일과 비밀, 무관한 변경을 점검하고 CLI가 커밋하지 않은 변경만 검토 후 별도로 커밋합니다.

## 완료 기준과 문제 해결

.NET 10 빌드/실행과 기존 사용자 기능의 회귀 결과, 임시 Windows 의존성과 최종 제거 조건이 명확해야 합니다. 이 단계의 성공은 **Linux 지원 완료가 아닙니다**. 원본의 파괴적 초기화를 새 Azure DB에 가져가지 않습니다. 중단된 변환은 [문제 해결](08-troubleshooting.md)을 확인하고 미완료로 남깁니다.
