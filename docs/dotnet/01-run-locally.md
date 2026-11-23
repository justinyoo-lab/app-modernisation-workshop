# .NET 1. 원본 앱을 로컬에서 실행하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: 준비](00-setup.md) | [다음: 평가와 계획](02-assess-and-plan.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

현대화 전 Windows 원본의 동작을 **Copilot app에서 Windows 터미널을 통해** 확인합니다. 사전 점검/다운로드를 마쳤고 VS 2022/2026 IDE 또는 독립 Build Tools의 웹 MSBuild 타깃, .NET Framework 4.8 이상 런타임과 4.8 Targeting Pack, IIS Express, LocalDB, MSMQ, .NET 10 SDK가 있어야 합니다. **IDE 실행은 선택 사항**입니다.

터미널은 **Windows PowerShell 7**입니다. 워크숍 자료 루트에 있고 기본 다운로드 위치를 사용했다면 다음 명령으로 앱 루트에 이동합니다. 사용자 지정 경로를 선택했다면 그 폴더로 이동하세요. 이미 앱 루트에 있다면 이동 명령을 건너뜁니다.

```powershell
Set-Location ./dotnet
```

이후 명령은 **앱 루트**에서 실행합니다. Copilot app에서 **이 앱 폴더**를 프로젝트로 추가하고 **This computer**, **Current checkout**을 사용합니다. 워크숍 최상위나 `docs/dotnet`을 열지 않습니다. 별도 worktree 세션을 사용하면 앱과 도우미가 그 작업 경로에도 있는지 확인하고 `-AppPath`에는 반드시 **그 세션의 실제 앱 경로**를 전달합니다. Modernize CLI용 터미널과 IIS Express용 장기 실행 터미널은 분리합니다.

```powershell
Get-Location
git rev-parse --show-toplevel
git branch --show-current
git status --short
```

```powershell
Get-Content ./ContosoUniversity.csproj | Select-String TargetFrameworkVersion
Get-Service MSMQ
dotnet --list-sdks
```

`.csproj`의 `v4.8`이 원본 대상입니다. README/packages.config 표기만 보고 타깃을 바꾸지 않습니다. 최초 현대화 전에는 원본 프레임워크를 유지합니다.

아래 절차는 다운로드 스크립트가 고정한 [원본 커밋 `7c1bf47`](https://github.com/Azure-Samples/dotnet-migration-copilot-samples/tree/7c1bf47b7e2627fe5a1c764716638815d35e0282/ContosoUniversity)의 `.sln`, `.csproj`, `packages.config`, `Web.config`와 초기화/큐 코드를 기준으로 합니다. fixture 검사는 실제 샘플의 복원/빌드/브라우저 검증을 대신하지 않으므로 사용 환경에서 아래 기준 동작까지 확인합니다.

## 1. Copilot app에서 복원과 빌드

Copilot app 채팅에 다음과 같이 요청하거나 참가자가 직접 실행합니다. 이 단계에서는 Modernize CLI로 소스를 변경하지 않습니다.

```text
이 세션의 실제 앱 루트를 확인하고 Windows PowerShell 7에서 원본을 복원/빌드해 줘.
Visual Studio IDE를 열지 말고, 워크숍 scripts/run-dotnet-original.ps1에
-AppPath로 이 앱의 절대 경로를 전달해 실행해 줘. 지금은 -Run을 붙이지 마.
고정된 net48 타깃과 packages.config를 유지하고 full-framework MSBuild.exe를 사용해.
명령/경로/종료 코드와 오류를 기록하고, 실패하면 앱을 실행하거나 업그레이드하지 마.
도구 설치, OS 설정 변경, DB 초기화는 아직 하지 마.
```

참가자가 직접 실행해도 같은 경로입니다. 기본 폴더 구조에서는 앱 루트에서:

```powershell
../scripts/run-dotnet-original.ps1 -AppPath .
if ($LASTEXITCODE -ne 0) { throw '원본 복원/빌드 실패. 다음 단계로 진행하지 마세요.' }
```

사용자 지정 다운로드 위치라면 `../scripts` 대신 **워크숍 자료 폴더의 도우미 절대 경로**를 지정합니다. 도우미는 `vswhere`로 IDE/Build Tools의 MSBuild와 웹 타깃을 찾고, 공백이 있는 경로도 인자로 보존합니다. 별도 `nuget.exe`나 Developer Command Prompt는 필요하지 않습니다. 원본은 솔루션과 프로젝트가 같은 폴더이며 `HintPath`가 `packages/...`를 참조하므로 다음 순서로 실행합니다.

```text
MSBuild.exe <앱 루트>/ContosoUniversity.sln /t:Restore /p:RestorePackagesConfig=true /p:RestoreRepositoryPath=<앱 루트>/packages
MSBuild.exe <앱 루트>/ContosoUniversity.sln /t:Build /p:Configuration=Debug
```

위 두 줄은 실행 구조 설명이며 실제 경로의 따옴표/버전 설정은 도우미가 처리합니다. 두 명령 모두 선택한 설치본의 `VisualStudioVersion` 및 `VSToolsPath`를 명시해 원본의 오래된 웹 타깃 기본값을 피합니다. 복원 실패 시 빌드하지 않고, 빌드 실패 시 IIS Express를 실행하지 않습니다. `dotnet restore/build/run`으로 대체하거나 NuGet의 TLS 검증을 끄지 않습니다.

## 2. DB 대상을 확인한 뒤 IIS Express 실행

**첫 HTTP 요청은 `Global.asax.cs`의 DB 초기화를 실행합니다.** 고정 샘플의 `Data/DbInitializer.cs`는 `EnsureCreated()`와 seed를 사용하며, 이 경로에서 모델 변경 시 DB를 자동 삭제/재생성한다고 가정해서는 안 됩니다. **실습 전용 DB만 사용하고 개인/업무 DB를 연결하지 않습니다.** 코드가 달라졌다면 초기화/삭제 경로를 다시 검토합니다.

```powershell
Select-String -Path ./Web.config -Pattern 'connectionString|NotificationQueuePath'
Get-Content ./Data/DbInitializer.cs
Get-Content ./Services/NotificationService.cs
```

원본 연결은 `(LocalDb)\MSSQLLocalDB`의 `ContosoUniversityNoAuthEFCore`, 큐는 `.\Private$\ContosoUniversityNotifications`입니다. 다른 실습도 같은 이름을 사용할 수 있으니 소유와 데이터 보존 필요를 확인하세요. 도우미는 연결 문자열 변경, LocalDB 인스턴스/큐 생성 또는 데이터 삭제를 직접 수행하지 않지만 앱 자체는 요청 처리 중 DB/큐에 쓰기 작업을 할 수 있습니다. 특히 원본 `NotificationService`는 큐가 없으면 생성하고 `Everyone`에 FullControl을 부여합니다. 전용 로컬 실습 환경에서만 사용하고, 공유 PC에서는 실행 전 관리자와 최소 권한 큐를 별도로 준비할지 검토합니다. 앱을 무조건 관리자 권한으로 올려 해결하지 않습니다.

LocalDB가 PATH에 없다면 설치 폴더의 `SqlLocalDB.exe` 절대 경로로 다음을 실행합니다.

```powershell
SqlLocalDB.exe info
SqlLocalDB.exe info MSSQLLocalDB
Get-Service MSMQ
```

없는 인스턴스를 임의로 여러 개 만들기 전에 `Web.config`와 실제 이름을 대조합니다. MSMQ는 Running이어야 합니다. 전용 DB 사용과 초기화 위험을 확인한 후 다음 요청 또는 같은 명령을 사용합니다.

```text
Web.config와 DB 생성/재생성 경로를 확인했고 실습 전용 데이터만 사용한다.
같은 실제 앱 루트에서 run-dotnet-original.ps1 -Run -AllowDatabaseInitialization으로
복원/빌드 후 IIS Express를 실행해 줘. 관리자 권한, 서비스/인증서/URL ACL 변경은 하지 마.
장기 실행 터미널을 유지하고 이 실행의 PID와 실제 localhost URL을 기록해 줘.
홈 화면뿐 아니라 아래 기준 동작은 내가 브라우저에서 확인할게.
```

```powershell
../scripts/run-dotnet-original.ps1 -AppPath . -Run -AllowDatabaseInitialization
```

도우미는 IIS Express 설치본의 `AppServer/applicationhost.config`를 기반으로 앱 내부 `.vs/workshop/applicationhost-<고유값>.config`를 생성합니다. 전역 IIS 설정, `Web.config`와 기존 `.vs` 설정은 바꾸지 않습니다. CLR v4 Integrated 풀과 원본 프로젝트의 **Windows 인증 활성/익명 인증 비활성**을 유지합니다. 기본 주소는 **`http://localhost:58801/`**입니다. 원본 IDE 프로필의 `https://localhost:44300/`과 달리, CLI 기본은 localhost 전용 HTTP 바인딩으로 인증서/HTTP.sys SSL 등록 없이 실행합니다. 외부 공개나 실제 비밀 데이터 전송에 사용하지 않습니다.

포트가 사용 중이면 해당 앱을 종료하지 말고 `-Port 58802` 등 빈 포트를 선택합니다. 브라우저에 출력된 주소를 직접 엽니다. 도우미는 브라우저/HTTP 요청을 자동 실행하지 않으며, 성공 종료 코드나 IIS 시작 로그만으로 DB/큐/화면 동작 성공이라 하지 않습니다.

IIS Express는 **전경 프로세스**입니다. Copilot app에서 실행할 때 명령 시간 제한으로 종료되지 않도록 장기 실행 터미널을 유지하고 PID를 기록하도록 요청합니다. 참가자가 직접 실행하면 이 터미널을 유지하고 다른 터미널/브라우저에서 검증합니다. 종료는 해당 터미널에서 `Q` 또는 `Ctrl+C`를 사용합니다. 자동 종료되면 오류와 종료 코드를 확인하고 실제 앱 응답은 미검증으로 남깁니다.

### 선택: 기존 IDE/HTTPS 프로필

1. Visual Studio IDE를 선호한다면 동일 앱 폴더의 `ContosoUniversity.sln`을 엽니다.
2. 솔루션의 NuGet 패키지를 복원하고 Build Solution을 실행합니다. Targeting Pack 오류와 NuGet 네트워크/인증 오류를 구분합니다.
3. 시작 프로젝트와 IIS Express 프로필을 확인합니다. `Web.config`의 LocalDB 연결 대상은 기본적으로 `(LocalDb)\MSSQLLocalDB`입니다.
4. 디버깅 없이 시작하거나 디버깅을 시작합니다. 기본 HTTPS 주소는 `https://localhost:44300/`이며 실제 실행 프로필의 주소를 사용합니다.

CLI에서도 HTTPS가 필요하면 별도의 IIS Express 사이트/SSL 바인딩과 인증서 신뢰를 직접 준비해야 합니다. 도우미는 이를 자동 등록하지 않습니다. 개발 인증서와 출처를 확인해 해결하고 브라우저 보안 경고를 무조건 무시하거나 TLS 검사를 끄지 않습니다.

## 기준 동작 기록

학생 목록/검색/페이지 이동, 학생 추가/수정/삭제, 강좌/강사/학과와 통계 화면을 확인합니다. 개인 정보가 없는 가짜 학생과 강좌 데이터를 사용하고 수행한 입력과 결과를 기록하세요.

1. `Courses`에서 `Create New` 또는 기존 강좌의 `Edit`를 선택합니다. `Teaching Material Image`에 개인 정보가 없는 5 MiB 이하의 실제 PNG 이미지를 첨부하고 저장합니다. 강좌 목록과 상세 화면에서 이미지를 확인합니다.
2. 강좌 등 개체를 생성하거나 수정한 뒤 화면 오른쪽 위에 알림이 표시되는지 확인합니다. `Notifications` 메뉴의 `Quick Test`도 사용할 수 있습니다. 다른 브라우저가 메시지를 먼저 가져갈 수 있으므로 한 창에서 확인하고 결과를 기록합니다.

MSMQ 오류가 나면 서비스 상태, 앱이 사용하는 private queue 이름, 생성/접근 권한과 트랜잭션 설정을 확인합니다. IIS Express를 무조건 관리자 권한으로 실행하는 대신 필요한 권한만 해결합니다. 홈 화면만 열린 상태를 성공으로 처리하지 않습니다.

## 기준선 커밋과 Copilot app

해당 IIS Express 터미널에서 `Q` 또는 `Ctrl+C`로 실행을 중지하고(IDE를 선택했다면 IDE 실행 중지), 변경/생성 파일을 확인합니다. 앱 폴더에는 별도의 `.git` 저장소가 없습니다. Git은 워크숍 루트 저장소를 사용하며, 저장소에 이미 있는 제외 규칙은 보존하면서 실습 생성물의 제외 규칙을 앱 폴더의 `.gitignore`에 보완합니다.

```powershell
Add-Content ./.gitignore "`n.azure/`n.vs/`n**/bin/`n**/obj/`npackages/`n*.mdf`n*.ldf`n.env`n.env.*"
git status --short
```

변경할 파일을 확인하고 스테이징합니다.

```powershell
git add .
```

스테이징된 내용을 검토합니다.

```powershell
git diff --cached --stat
git diff --cached
```

업로드 파일, 로그, 인증 토큰과 실제 연결 비밀이 포함되어 있으면 커밋하지 않습니다. 해당 파일을 스테이징에서 제외하고 제외 규칙을 보완한 뒤 다시 확인합니다. 검토가 끝난 후 기준선 커밋을 만듭니다.

```powershell
git commit -m "Baseline: verified .NET Framework sample"
```

Git 신원이 없으면 참가자가 워크숍 저장소 범위에 본인 설정을 추가합니다. 템플릿 저장소를 복제할 때 설정된 원격을 새로 만들 필요는 없습니다.

계속 같은 Copilot app 프로젝트와 실제 앱 경로에서 평가/현대화를 진행합니다. 앱 세션을 바꾸면 기준선 코드와 작업 경로가 같은지 확인합니다.

## 완료 기준과 문제 해결

원본 빌드, IIS Express와 LocalDB/MSMQ, 주요 화면과 데이터 동작을 확인하고 기준선 커밋을 남겨야 합니다. 실패한 원본 상태로 업그레이드를 시작하면 원인 구분이 어려워집니다. [문제 해결](08-troubleshooting.md)에서 Targeting Pack, MSMQ, 인증서 항목을 확인하세요.
