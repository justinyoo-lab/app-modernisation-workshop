# 3. JDK 25로 업그레이드하기

[전체 목차](../../README.md) | [Java 목차](README.md) | [이전: 평가와 계획](02-assess-and-plan.md) | [다음: Azure 서비스 이전](04-migrate-azure-services.md) | [문제 해결](08-troubleshooting.md)

## 목표

검토한 계획에 따라 앱을 Java 25로 업그레이드하고 Azure 이전에 필요한 코드와 배포 산출물을 준비합니다.

## 실습 범위

이 실습에서는 승인한 Modernize 계획을 실행해 Java와 Spring Boot를 업그레이드하고, Azure 서비스 이전 코드와 배포 산출물을 준비합니다.

| 단계 | 다루는 내용 | 이 단계에서 하지 않는 작업 |
| --- | --- | --- |
| 실습 3: JDK 25로 업그레이드하기 (이 문서) | Java 업그레이드, Azure 서비스 이전 코드와 배포 산출물 준비, 로컬 빌드 및 모의 테스트 | Azure 리소스 생성, 실제 Azure 연결, 앱 배포 |
| [4. Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md) | 이전된 애플리케이션 코드와 동작 검토, 필요한 수정과 외부 서비스 없는 테스트 | Azure 리소스 생성 및 연결 |
| [5. azd 배포 산출물 준비하기](05-prepare-azd.md) | Dockerfile, `azure.yaml`, Bicep, DB 초기화 절차와 배포 설정 검토 | 프로비저닝, DB 초기화, 이미지 게시, 배포 |
| [6. azd로 ACA에 배포하기](06-deploy-aca.md) | 승인 후 Azure 리소스 프로비저닝, DB 초기화, 로컬 이미지 빌드, 배포와 실제 기능 확인 | 승인하지 않은 리소스나 데이터 변경 |

## 실습 전 확인 사항

평가 보고서, 현대화 지침, `plan.md`, `tasks.json`을 커밋해 둡니다. [실습 2: 평가하고 계획 승인하기](02-assess-and-plan.md)에서 사용한 터미널을 계속 사용합니다.

## 승인한 계획 실행

앱 루트에서 JDK 8을 선택하고 Modernize CLI를 실행합니다. 계획의 첫 단계인 Java 8 기준 테스트부터 시작합니다.

```bash
# zsh/bash
source ../scripts/use-java.sh --jdk 8
git status --short
before=$(git rev-parse HEAD)
modernize
```

```powershell
# PowerShell
. ../scripts/use-java.ps1 -Jdk 8
git status --short
$before = git rev-parse HEAD
modernize
```

> [!NOTE]
>
> Modernize는 작업별로 커밋을 만들 수 있습니다. `$before`에 실행 직전의 커밋 ID를 저장해 두면, 실행 중 추가된 커밋과 변경 사항을 결과 검토 단계에서 확인할 수 있습니다.

화면에 표시되는 항목과 선택값은 다음과 같습니다. UI 표기는 설치된 버전에 따라 다를 수 있습니다.

| 항목 | 선택값 |
| --- | --- |
| How would you like to modernize your app? | Execute |
| Execute modernization plan | 선택 |
| Select a plan | `modernization-plan` (java) |
| Execute the plan | 선택 |

화면의 안내에 따라 계획을 선택하고 `Enter`를 눌러 실행합니다. 이후 에이전트가 질문하면 내용을 읽고 권장 옵션을 선택하거나 직접 답변합니다.

> [!CAUTION]
>
> 실행이 중간에 멈추고 더 이상 진행되지 않을 수 있습니다. 이때는 Copilot app에서 원인을 확인하고 문제를 해결한 뒤 계속 진행합니다.

## 업그레이드 결과 검증

업그레이드 결과를 검증하려면 앱 루트에서 아래 명령을 실행합니다.

```bash
# zsh/bash
source ../scripts/use-java.sh --jdk 25
./mvnw -version
./mvnw clean verify
```

```powershell
# PowerShell
. ../scripts/use-java.ps1 -Jdk 25
./mvnw.cmd -version
./mvnw.cmd clean verify
```

`BUILD SUCCESS`를 확인합니다. 실패하면 문제를 해결한 뒤 다음 단계로 진행합니다.

아래 명령은 web/worker를 실행하지 않고, 외부 서비스를 모의 객체로 대체한 테스트로 동작을 검증합니다.

```bash
# zsh/bash
./mvnw -pl web,worker -am verify
```

```powershell
# PowerShell
./mvnw.cmd -pl web,worker -am verify
```

> [!NOTE]
>
> 여기서는 web/worker를 실행하지 않고 빌드와 모의 테스트만 확인합니다. 테스트가 실패하면 Copilot app에서 원인을 확인하고 수정합니다.

## 실행 결과 커밋하기

앱 루트에서 `$before` 이후 생성된 커밋과 아직 커밋하지 않은 변경을 확인합니다. Modernize가 이미 커밋한 변경은 다시 스테이징할 필요가 없습니다. 커밋할 변경이 남아 있다면 `<검토한-파일-경로>`를 실제 경로로 바꿔 해당 파일만 추가합니다. 스테이징된 내용을 검토하고, 남은 변경이 없으면 이 단계를 건너뜁니다.

```text
git status --short
git log --oneline "$before..HEAD"
git diff "$before"
git add <검토한-파일-경로>
git status --short
git diff --cached --stat
git diff --cached
```

검토한 변경만 포함됐고 비밀정보나 불필요한 파일이 없을 때 커밋합니다.

```bash
git commit -m "Modernize: upgrade Java application"
```

## 완료 및 다음 단계

- [ ] Maven Wrapper와 테스트가 JDK 25를 사용하고 `clean verify`가 통과했습니다.
- [ ] web/worker의 모의 테스트가 통과했습니다.
- [ ] Modernize가 만든 커밋과 아직 커밋하지 않은 변경을 검토하고, 필요한 변경만 커밋했습니다.
- [ ] 이 단계에서 실제 Azure 리소스 연결이나 앱 실행을 검증하지 않았음을 확인했습니다.

위 항목을 모두 마쳤다면 [4. Azure 서비스로 의존성 이전하기](04-migrate-azure-services.md)로 이동해 이전 코드와 동작을 검토합니다.
