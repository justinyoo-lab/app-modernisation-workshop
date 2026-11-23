# .NET 2. 평가하고 계획 승인하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: 원본 실행](01-run-locally.md) | [다음: 업그레이드](03-upgrade.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

원본 동작과 기준선 커밋이 있는 **앱 루트(`dotnet`)**에서 Copilot app의 `/terminal`을 열고 **Windows PowerShell 7**을 사용합니다. 평가와 계획은 Modernize CLI에 전달합니다. 앱 채팅의 맥락, 모델과 승인 상태가 별도 CLI에 공유된다고 가정하지 않습니다.

CLI 실행 중 같은 파일 수정을 앱 채팅에 맡기지 않습니다. 앱의 Plan 모드는 CLI의 실행 권한을 제한하지 않습니다. 설치, 외부 서비스 사용과 모델 사용량을 확인하고 필요한 동의를 받은 뒤 진행합니다.

## 앱 평가

```powershell
modernize
```

**Assess**, **Current folder**, **local**을 선택합니다. 실제 `.sln`/`.csproj`가 있는 폴더 하나를 대상으로 **Upgrade**, **Cloud Readiness**, **Full analysis**를 선택하고 목표는 **.NET 10**, **Linux Azure Container Apps**로 맞춥니다. UI 표기는 설치 버전의 안내를 따릅니다. Full analysis의 구조, API, 설정, 업무 흐름, 의존성과 데이터 모델을 확인합니다. Java용 Security 평가를 .NET 보안 검사 완료로 해석하지 않습니다.

명령형 진입은 다음과 같습니다. 이 명령만으로 분석 범위와 목표까지 지정되는 것은 아니므로 실제 설정을 확인합니다.

```powershell
modernize assess --source . --delegate local --format markdown
```

앱 코드/패키지 수정, Azure 리소스 생성과 배포는 평가 범위에 넣지 않습니다. 추가 설치는 대상과 영향을 확인해 별도로 승인합니다. 보고서의 실제 경로, 실패/미분석 항목과 `git status --short`를 확인합니다. 도움말의 기본 출력은 `.github/modernize/assessment`이지만 실제 보고서 파일명을 추측하지 않습니다.

고정 샘플의 대상은 **`v4.8`**입니다. README 표기만 보고 타깃을 바꾸지 않습니다. MVC 5/System.Web, EF Core/LocalDB, MSMQ, 파일 저장, 인증/쿠키/세션, 초기 데이터 생성과 DB 재생성 경로, 테스트와 Linux 전환 위험의 근거 파일을 검토합니다. 보고서가 생긴 것만으로 평가 완료를 선언하지 않습니다.

## 워크숍 제약 기록

앱 루트의 `.github/skills/dotnet-aca-workshop/SKILL.md`에 다음을 저장합니다. Copilot app 채팅에 이 파일의 작성만 맡겨도 됩니다.

```markdown
---
name: dotnet-aca-workshop
description: Preserve Contoso University behavior while upgrading to .NET 10 and preparing Linux Azure Container Apps deployment.
---

# 워크숍 제약

- 현재 승인한 계획만 수행하고 설치/외부 서비스 사용은 별도 승인한다.
- 원본은 .NET Framework v4.8/MVC 5이며 최종 목표는 .NET 10/ASP.NET Core이다.
  더 새 SDK가 있어도 목표를 바꾸지 않는다. 최종 환경은 Linux Azure Container Apps다.
- Razor/MVC, 라우팅, 유효성 검사, CRUD/검색/페이지 이동, 큐/파일 기능을 보존한다.
  별도 SPA로 다시 쓰지 않는다.
- LocalDB는 Azure SQL, MSMQ는 Service Bus, 로컬 파일은 private Blob으로 이전한다.
  Windows용 패키지 이름만 바꾸고 Linux 지원 완료라고 하지 않는다.
- 임시 Windows 어댑터의 범위와 최종 제거 조건을 명시한다.
- 관리 ID, 최소 권한과 TLS를 사용한다. 비밀은 코드/설정/Git에 넣지 않는다.
  DB 내부 사용자/권한과 ARM 역할, migration 실행 주체를 구분한다.
- EnsureDeleted, 데이터 삭제/재생성 및 파괴적인 seed를 제거한다.
  새 데모 DB의 migration/seed는 참가자가 승인하고 직접 실행하는 별도 절차로 만든다.
- 메시지 중복/재시도/dead-letter와 소비자 수명 주기를 명확히 한다.
- private Blob의 인증된 업로드/조회를 유지하며 공개 컨테이너로 우회하지 않는다.
- Data Protection 키와 앱 이름/저장 경로를 revision/인스턴스 간 보존한다.
- azd/Bicep과 로컬 컨테이너 엔진을 사용한다.
  원격 이미지 빌드, ACR Tasks, az acr build는 사용하지 않는다.
- 기준 테스트, .NET 10 업그레이드, Azure 코드와 azd 산출물을 별도 계획으로 나눈다.
  변경 파일, 검증 명령, 테스트 수와 중단/복구 기준을 기록한다.
- Azure 리소스 생성, DB 변경/데이터 이전, 이미지 게시, 배포와 삭제는
  계획 실행에 포함하지 않는다. 참가자가 별도 승인 후 직접 실행한다.
- 실패한 테스트를 삭제/건너뛰지 않는다. 실제 결과와 미실행 통합 항목을 구분한다.
```

앱 루트와 Git 루트가 다르므로 스킬의 자동 발견을 가정하지 않고 계획 입력에 경로를 명시합니다. 스킬은 권한 제한 장치가 아닙니다.

## 네 계획과 첫 계획 생성

| 계획 | 범위와 생성 시점 |
| --- | --- |
| `ws03-baseline` | 지금 생성. 원본 Windows 기준 테스트 보강과 실행 |
| `ws03-upgrade` | 기준 테스트 확인 후 생성. .NET 10 전환과 로컬 회귀 |
| `ws04-azure-code` | 업그레이드 검토 후 생성. Azure 연동과 Windows 의존성 제거 |
| `ws05-azd-assets` | 코드 계약 확정 후 생성. Dockerfile, azure.yaml, Bicep과 DB 준비 절차 작성 |

실제 평가 보고서 파일 경로로 바꾸고 첫 계획만 생성합니다. `--assess-file-path`가 설치본 도움말에 없다면 보고서 경로를 목표 문장에 넣고 반영 여부를 확인합니다.

```powershell
$assessment = "<실제-평가-보고서>"
$goal = '.github/skills/dotnet-aca-workshop/SKILL.md와 평가 보고서를 읽고 원본 v4.8의 기준 테스트 보강과 실행만 계획해 줘. 기존 UI/CRUD/큐/파일 동작과 DB 초기화 위험을 보존해 검증하고 LocalDB/MSMQ가 필요한 검사의 조건을 명시해 줘. 업그레이드, Azure 이전, 리소스 생성과 배포는 제외하고 지금은 계획만 작성해 줘.'
modernize plan create $goal --source . --language dotnet --plan-name ws03-baseline --assess-file-path $assessment
```

## 검토와 완료 기준

실제 `plan.md`, `tasks.json`과 사용 스킬의 저장 경로를 기록하고 함께 읽습니다. 버전별 출력 경로를 추측해 복제하지 않습니다. 기준 테스트 이외 작업, 설치/클라우드 변경, 앱 외부 변경과 비밀 커밋이 포함되지 않았는지 확인합니다. `--source .`는 Git 커밋 범위를 격리하지 않습니다.

계획을 수정하면 두 파일의 의미를 맞추고 다시 검토합니다. 평가와 `ws03-baseline`만 승인한 뒤 [업그레이드](03-upgrade.md)에서 실행합니다. 최종 목표를 .NET 8/9/11이나 Windows 컨테이너로 바꾼 계획은 승인하지 않습니다.
