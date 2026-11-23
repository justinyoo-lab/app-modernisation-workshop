# .NET 준비: 저장소 생성부터 샘플 다운로드까지

[전체 목차](../../README.md) | [.NET 목차](README.md) | [다음: 원본 실행](01-run-locally.md) | [문제 해결](08-troubleshooting.md)

## 실행 환경

원본 .NET Framework 앱은 **Windows**에서 진행합니다. Copilot app의 **PowerShell 7 터미널, MSBuild와 IIS Express**를 사용하며 Visual Studio IDE를 열 필요는 없습니다.

[GitHub Copilot app](https://gh.io/app), [Git](https://git-scm.com/downloads), [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)을 준비합니다. Windows PowerShell 5.1에서도 준비 스크립트를 직접 실행할 수 있으며 PowerShell 7에 위임합니다. PowerShell 7이 없으면 설치 도우미만 별도 동의를 받아 설치를 제안합니다.

## 1. 템플릿으로 저장소 만들고 클론하기

1. [워크숍 템플릿](https://github.com/devkimchi/app-modernisation-workshop)에서 **Use this template > Create a new repository**를 선택합니다.
2. Owner는 본인 **개인 계정**으로 지정합니다. 공개할 계획이 없다면 **Private**을 선택하고 **Include all branches**는 선택하지 않습니다.
3. 아래 URL과 폴더를 실제 값으로 바꿔 복제합니다. GitHub CLI를 아직 설치하지 않았다면 Git을 사용합니다.

```powershell
git clone "https://github.com/<본인-계정>/<저장소-이름>.git"
Set-Location "<저장소-이름>"
```

복제한 폴더가 **워크숍 루트**입니다. 템플릿 자체를 직접 클론하거나 포크하지 않습니다. 템플릿으로 만든 저장소는 독립된 이력을 가지며 원본의 이후 변경을 자동으로 받지 않습니다.

## 2. 필수 도구 점검과 설치

### 실행 정책과 점검

첫 스크립트 실행 전에 현재 창의 정책을 확인합니다.

```powershell
Get-ExecutionPolicy
```

`Restricted`이면 현재 창에만 다음을 적용합니다. 창을 닫으면 원래 정책으로 돌아가므로 새 창에서도 필요하면 다시 적용합니다. 시스템과 사용자 범위의 정책은 바꾸지 않습니다. 조직 정책 때문에 변경할 수 없으면 관리자에게 문의합니다.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

**워크숍 루트**에서 점검합니다.

```powershell
./scripts/check-prerequisites.ps1 -Track dotnet
```

| 결과 | 색상 | 할 일 |
| --- | --- | --- |
| ![PASS](https://img.shields.io/badge/PASS-green) | 초록 | 해당 검사 통과. 앱 실행이나 배포 성공을 뜻하지 않음 |
| ![FAIL](https://img.shields.io/badge/FAIL-red) | 빨강 | 부족한 도구나 설정을 보완한 뒤 다시 점검 |
| ![WARN](https://img.shields.io/badge/WARN-yellow) | 노랑 | 오류 내용과 검사 제한 확인 |
| ![MANUAL](https://img.shields.io/badge/MANUAL-cyan) | 청록 | Copilot 로그인, 라이선스, 조직 정책, 터미널 접근과 Azure 권한을 직접 확인 |
| ![INFO](https://img.shields.io/badge/INFO-blue) | 파랑 | 참고 정보 |

### 도구 설치와 업데이트

누락된 도구를 설치하고 업데이트 가능한 도구는 **항목별로 `y`로 승인한 경우에만** 갱신합니다. 최신 버전으로 확인된 도구는 묻지 않고 건너뜁니다. 누락된 도구만 설치하려면 `-Update`를 생략합니다. CI와 비대화형 환경에서는 설치를 승인하지 않습니다.

```powershell
./scripts/install-prerequisites.ps1 -Track dotnet -Update
```

설치 도우미는 설치와 Azure 준비 후 `check-prerequisites.ps1` 점검을 다시 실행하며, `[INFO]` 메시지로 실행할 스크립트를 알립니다.

| 대상 | 설치와 업데이트 |
| --- | --- |
| PowerShell 7 | winget으로 설치하고 출처가 확인된 지원 설치본만 업데이트 |
| Node.js 22 이상 | [nvm-windows](https://github.com/nvm-windows/nvm)로 설치. 없거나 22 미만이면 22.x, 업데이트 시 현재 메이저의 최신 정식 버전 추가 |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) | winget으로 누락된 도구만 설치. 업데이트는 원래 설치 관리자로 직접 수행 |
| [GitHub CLI](https://cli.github.com/) 2.45.0 이상 | winget `GitHub.cli` |
| [Modernize CLI](https://github.com/microsoft/modernize-cli) | winget `GitHub.Copilot.modernization.agent` |
| [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) | winget으로 설치. `-Update`에서는 최신 정식 10.x보다 낮을 때 별도 동의를 받아 업데이트. 다른 메이저 SDK와 `global.json`은 유지 |

Node.js와 npm은 Modernize CLI의 배포 도구 서버가 `npx`를 사용할 수 있어 두 트랙 모두 준비합니다. .NET의 실제 서버 호출 경로는 별도 리허설 항목이며 Node.js 22 이상이라는 워크숍 기준은 유지합니다.

관리자 승인과 설치 관리자 약관은 직접 확인합니다. 업데이트가 예약된 PowerShell은 현재 창을 닫은 뒤 작업 결과를 확인하고 새 터미널에서 다시 점검합니다. 설치나 업데이트가 끝나지 않으면 [문제 해결](08-troubleshooting.md#사전-준비-수동-복구)을 확인합니다.

### Windows 빌드 및 실행 도구 준비

아래 구성요소는 도우미가 **자동 설치하지 않습니다**. 점검에서 누락된 항목만 준비합니다.

| 구성요소 | 수동 준비 |
| --- | --- |
| Framework 웹 빌드 도구 | [Visual Studio IDE 또는 Build Tools](https://visualstudio.microsoft.com/downloads/). 지원되는 2022/2026 설치본의 IDE는 **ASP.NET 및 웹 개발**, Build Tools는 **Web development build tools** 워크로드 |
| .NET Framework | **4.8 이상 런타임과 4.8 Targeting Pack** 모두 필요. 런타임이나 .NET 10 SDK만으로 대체할 수 없음 |
| IIS Express | Visual Studio Installer 개별 구성요소 또는 [IIS Express 10](https://www.microsoft.com/download/details.aspx?id=48264) |
| SQL Server Express LocalDB | Visual Studio Installer 또는 [SQL Server Express](https://www.microsoft.com/sql-server/sql-server-downloads)의 LocalDB 옵션. 실습 전용 DB 사용 |
| MSMQ Server | [Windows 기능 활성화](https://learn.microsoft.com/dotnet/framework/wcf/samples/installing-message-queuing-msmq) 후 필요한 재부팅 완료. MSMQ 서비스가 Running인지 확인 |

### 직접 준비할 항목

- **Azure 권한**: 구독, 테넌트, 리전, 쿼터, 역할 할당과 DB Entra 관리자 설정 권한을 확인합니다. Contributor만으로 역할 할당 권한이 확보되지는 않습니다. 필요한 범위만 요청하고 구독 전체 Owner를 무조건 요청하지 않습니다.
- **컨테이너 엔진**: [Docker Desktop](https://docs.docker.com/desktop/)을 설치하고 Linux containers 모드로 시작합니다. [Podman](https://podman.io/docs/installation)은 [문제 해결](08-troubleshooting.md#대체-엔진-설정)을 따릅니다. 도우미는 엔진을 자동 설치하지 않습니다.
- **인증**: 로그인, 구독 변경과 공급자 등록은 항목별로 승인합니다. 점검 스크립트는 조회만 수행합니다.

## 3. Copilot app과 Modernize CLI 준비

Copilot app에 로그인하고 계정의 라이선스와 조직 정책을 확인합니다. **This computer**, 기존 복제본의 **Current checkout** 세션에서 `/terminal`을 열고 확인합니다.

```powershell
gh --version
gh auth status
modernize --version
modernize assess --help
modernize plan create --help
modernize plan execute --help
```

gh에 로그인하지 않았다면 참가자가 `gh auth login`을 직접 수행합니다. gh 인증, 앱 로그인, `az login`, `azd auth login`은 별개이며 gh 인증 성공만으로 모델 사용 권한이 확인되지는 않습니다. `modernize help models`로 사용할 모델을 확인합니다. 앱의 모델과 승인 설정이 별도 프로세스인 CLI에 자동 적용된다고 가정하지 않습니다.

## 4. 샘플 다운로드하기

같은 **워크숍 루트**에서 실행합니다.

```powershell
./scripts/download-sample.ps1 -Track dotnet
```

대상 `dotnet` 폴더는 없거나 비어 있어야 합니다. `dotnet/ContosoUniversity.sln`을 확인한 뒤 [원본 실행](01-run-locally.md)으로 이동합니다. 개인 실습 복제본에서는 원본 실행 후 생성 파일과 비밀을 제외하고 기준선 커밋을 만듭니다. 도우미는 앱을 커밋하거나 별도 `.git`을 만들지 않습니다.
