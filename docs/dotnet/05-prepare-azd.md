# .NET 5. Linux 컨테이너와 azd 배포 산출물 준비하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: Azure 서비스 이전](04-migrate-azure-services.md) | [다음: ACA 배포](06-deploy-aca.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

Azure 의존성 코드가 준비된 **앱 루트**, Copilot app PowerShell 7 터미널에서 Modernize CLI로 Dockerfile, `azure.yaml`, Bicep을 준비합니다. Docker Desktop은 Linux containers 모드여야 합니다. 이 단계에서는 리소스를 만들지 않습니다.

## 배포 산출물 계획

다음 입력을 앱 루트의 `ws05-azd-assets-input.txt`에 UTF-8로 저장합니다.

```text
.github/skills/dotnet-aca-workshop/SKILL.md와 실제 Azure 코드/환경 변수 계약을 읽고
.NET 10 앱을 Linux Azure Container Apps에 배포할 산출물 생성을 계획해 줘.
대상은 앱 루트의 azure.yaml, Dockerfile, .dockerignore와 infra/ Bicep이다.
지금은 계획만 작성하고 기존 기능을 유지해 줘.

- 웹 서비스 이름은 web, language: docker, host: containerapp으로 설정한다.
- 로컬 Docker 엔진을 사용하고 AZD_CONTAINER_RUNTIME=docker로 맞춘다.
- docker.remoteBuild: false, docker.platform: linux/amd64를 명시한다.
- 공식 .NET 10 SDK/ASP.NET Core Linux 이미지로 multi-stage 빌드를 구성한다.
  mcr.microsoft.com/dotnet/sdk:10.0, aspnet:10.0의 실제 manifest를 확인한다.
- 실제 프로젝트와 의존성 경로를 사용하고 DLL 이름을 추측하지 않는다.
- 비루트 사용자, ASPNETCORE_HTTP_PORTS=8080, ingress targetPort=8080을 맞춘다.
  IIS/Windows 컨테이너, MSMQ와 LocalDB에 의존하지 않게 한다.
- readiness/liveness를 구현하고 외부 장애가 재시작 폭주로 이어지지 않게 구분한다.
- 웹 프로세스 내 Service Bus 소비자는 우선 minReplicas=1/maxReplicas=1로
  유지한다. 소비자를 분리하려면 계획 변경과 별도 서비스/비용 승인을 받는다.
- ACR Basic, ACA environment, Log Analytics, Azure SQL, Service Bus queue,
  private Blob 및 관리 ID/최소 권한을 Bicep으로 정의한다.
- ACR admin 계정 대신 관리 ID pull을 구성하고 로컬 azd 게시 주체의
  push 권한을 별도로 확인한다. ACR Tasks/az acr build는 사용하지 않는다.
- AZURE_CONTAINER_REGISTRY_ENDPOINT, AZURE_RESOURCE_GROUP,
  AZURE_WEB_APP_NAME, WEB_URI를 출력한다.
- azd-service-name 태그 또는 resourceName으로 web과 ACA 리소스를 연결한다.
- DB Entra 관리자, SQL 내부 사용자/권한과 migration을 준비할 별도 절차를
  생성한다. 기존 DB를 삭제하거나 덮어쓰는 hook은 만들지 않는다.
  이 계획은 절차 작성까지만 포함하고 DB 사용자/권한/migration은 실제 실행하지 않는다.
- Data Protection 키는 private Blob 등에 지속하고 새 revision에서도 재사용한다.
- 로컬 참가자와 ACA에서 SQL까지 실제 연결되는 네트워크 경로를 설계한다.
  공개 DB라면 확인한 클라이언트/egress IP만 허용한다. 전체 IP 허용은 금지한다.
  ACA inbound static IP를 outbound IP로 오인하지 않는다.
  제한된 경로를 확보할 수 없으면 VNet/private 연결과 추가 비용 승인을 제안한다.
- .azure/, 비밀, 로그와 로컬 빌드 산출물을 Git/이미지 컨텍스트에서 제외한다.

리전/SKU/쿼터/비용, 역할 할당과 DB 관리 권한, 이미지 태그 정책을 설명해 줘.
hooks와 호출 스크립트 검토, 구문/단위 검사를 계획에 포함해 줘.
이미지 게시, 프로비저닝, DB 변경, 배포와 삭제는 작업 목록에 넣지 마.
참가자가 별도 승인 후 직접 실행할 작업으로 구분해 줘.
```

```powershell
$goal = Get-Content ./ws05-azd-assets-input.txt -Raw -Encoding utf8
modernize plan create $goal --source . --language dotnet --plan-name ws05-azd-assets
```

실제 `plan.md`와 `tasks.json`을 함께 읽고 산출물 작성과 로컬 검증 범위를 승인합니다. 무관한 변경과 비밀이 없는지 확인하고 실행 전 커밋을 기록합니다.

```powershell
git status --short
$before = git rev-parse HEAD
modernize plan execute "승인한 ws05-azd-assets와 워크숍 스킬에 따라 파일 작성과 로컬 검증만 수행해 줘. 프로비저닝, DB 변경, 이미지 게시, 배포와 삭제는 실행하지 마." --source . --language dotnet --plan-name ws05-azd-assets --delegate local
```

실행 후 자동 커밋과 미커밋 변경을 함께 검토합니다. 앱 외부 파일, 생성물과 비밀도 확인합니다.

```powershell
git status --short
git log --oneline "$before..HEAD"
git diff "$before..HEAD"
git diff
git diff --cached
```

## azure.yaml과 컨테이너 검토

아래는 **설정 형태 예시**이며 전체 배포 파일이 아닙니다. `language: dotnet` 자동 빌드 방식과 혼용하지 않습니다.

```yaml
services:
  web:
    project: .
    language: docker
    host: containerapp
    docker:
      path: ./Dockerfile
      context: .
      remoteBuild: false
      platform: linux/amd64
```

Dockerfile의 `dotnet publish` 대상과 ENTRYPOINT DLL이 생성된 프로젝트 구조와 일치해야 합니다. `net10.0-windows`, Windows 전용 DLL 또는 IIS Express 설정으로 컨테이너를 실행하지 않습니다. 빌드 성공과 Linux 실행 성공은 다릅니다.

이미지 태그는 `latest` 반복 사용 대신 빌드별 고유 식별자를 사용합니다. ACR pull 인증과 push 인증은 주체가 다릅니다. `azure.yaml`의 web과 Bicep 태그/출력의 연결도 확인합니다.

루트/서비스 수준의 **모든 azd hooks와 호출 스크립트**를 읽습니다. 명령 수준 hook은 앱 루트, 서비스 수준 hook은 `project` 경로에서 실행됩니다. 셸과 상대 경로를 확인하고 DB 초기화나 자동 배포를 `postprovision`에 숨기지 않습니다. 오류를 숨기는 `continueOnError: true`를 기본값으로 두지 않습니다. 생성된 산출물을 `azd init --from-code`로 다시 생성하지 않습니다.

## 비용과 배포 승인

Azure SQL, ACR, Service Bus, 로그, 최소 replica와 네트워크 자원은 비용이 발생할 수 있습니다. [가격 계산기](https://azure.microsoft.com/pricing/calculator/)와 실제 리전/SKU 지원을 확인합니다. 무료 구독의 크레딧/쿼터가 모든 서비스를 보장하지 않습니다.

SQL 방화벽의 "Azure 서비스 허용"은 본인 구독만 허용하는 기능이 아닙니다. 자동으로 켜거나 전체 IP 범위를 열지 않습니다. 관리 ID 인증과 네트워크 접근은 별도로 성립해야 합니다.

## 완료 기준과 문제 해결

Dockerfile/`azure.yaml`/Bicep, 포트/비루트 사용자, Data Protection, SQL 초기화, 네트워크, 비용과 정리 범위를 검토하고 참가자가 생성 범위를 승인해야 합니다. 실제 로컬 이미지 빌드는 실습 6의 `azd package`로 확인합니다. 문제는 [문제 해결](08-troubleshooting.md)을 참고합니다.
