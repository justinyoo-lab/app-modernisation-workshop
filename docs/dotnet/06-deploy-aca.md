# .NET 6. azd로 ACA에 배포하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: azd 준비](05-prepare-azd.md) | [다음: 정리](07-cleanup.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

참가자가 승인한 인프라를 만들고 .NET 10 Linux 이미지를 로컬에서 빌드한 뒤 ACA에 배포합니다. 실행 위치는 Copilot app 터미널의 **앱 루트**, 셸은 **Windows PowerShell 7**입니다. Modernize 계획 실행에 실제 Azure 변경을 맡기지 않습니다. Docker 서버, 구독, 권한과 DB 접근 경로를 확인합니다. 대체 엔진은 [문제 해결](08-troubleshooting.md#대체-엔진-설정)을 참고합니다.

## azd 환경

```powershell
$env:AZD_CONTAINER_RUNTIME = 'docker'
$env:AZD_NON_INTERACTIVE = 'false'
azd version
azd auth login --check-status
az account show --query "{name:name,id:id}" --output table
azd env new "<개인별-고유-환경명>"
azd env set AZURE_SUBSCRIPTION_ID "<본인-구독-ID>"
azd env set AZURE_LOCATION "<지원되는-리전>"
```

`<...>`를 실제 값으로 바꿉니다. 기존 환경은 새로 만들지 않고 `azd env list`와 `azd env select "<환경명>"`을 사용합니다. `az`와 `azd`는 별도 로그인입니다. `az account show`와 `azd env get-value AZURE_SUBSCRIPTION_ID`의 구독을 대조합니다. `.azure` 설정/비밀을 Git이나 채팅에 넣지 않습니다.

azd는 환경에 따라 자동 비대화형 모드가 될 수 있습니다. 설치본의 `AZD_NON_INTERACTIVE=false` 지원을 확인합니다. 이 설정은 비용/데이터 승인이나 hook 검토를 대신하지 않습니다. 승인 질문이 반드시 나온다고 가정하지 않고 명령마다 범위를 직접 확인합니다.

## 프로비저닝과 DB 초기화

각 명령의 결과를 확인한 뒤 다음 단계로 진행합니다. 모든 hooks를 검토하고 설치본 `azd provision --help`가 지원하면 변경을 미리 봅니다. 미리보기도 Azure 접근과 hook 실행을 포함할 수 있으며 비용 견적이나 데이터 안전을 보장하지 않습니다.

```powershell
azd provision --preview
```

구독, 리전, SKU, 권한, 네트워크와 비용을 승인한 뒤 실제로 생성합니다.

```powershell
azd provision
```

생성한 Azure SQL에 Entra 관리자와 앱 관리 ID의 DB 사용자/권한을 준비하고 승인한 migration을 적용합니다. 구체적인 명령은 실습 5에서 생성/검토한 초기화 절차를 사용합니다. 리소스 RBAC 할당은 SQL 내부 사용자 생성을 대신하지 않습니다.

원본의 파괴적 초기화나 `EnsureDeleted`를 실행하지 않습니다. migration은 지정한 새 데모 DB인지 확인하고 실행합니다. 이 단계가 실패하면 앱 배포로 넘어가지 말고 권한/네트워크/스키마 오류를 해결합니다.

## 로컬 빌드와 배포

```powershell
azd package
```

명령 직후 `$LASTEXITCODE`로 종료 코드가 `0`인지 확인하고 로그에서 선택 엔진, **.NET 10 Linux/amd64** 이미지와 실제 프로젝트 빌드를 확인합니다. 실패했거나 빌드 결과를 확인하지 못했다면 배포하지 않습니다.

```powershell
azd deploy
```

`azd deploy`는 이미지를 다시 빌드할 수 있습니다. package 후 소스를 바꾸지 않고 실제 배포 이미지 tag/digest를 기록합니다. ACR 게시와 새 revision 업데이트가 성공했는지 확인한 뒤 조회합니다.

```powershell
azd show
```

엔진 오류를 숨기기 위해 remote build/ACR Tasks로 전환하지 않습니다.

`azd up`은 여러 단계를 한 번에 수행할 수 있지만 이 실습은 승인 범위와 실패 위치를 알 수 있도록 명령을 나눕니다.

## 상태와 사용자 기능 검증

실습 5에서 정의한 실제 출력 계약을 사용합니다. 환경 값이 없으면 추측하지 말고 출력과 서비스 연결부터 확인합니다.

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
$app = azd env get-value AZURE_WEB_APP_NAME
az containerapp show --resource-group $rg --name $app --query "{state:properties.provisioningState,ready:properties.latestReadyRevisionName,fqdn:properties.configuration.ingress.fqdn}" --output json
az containerapp logs show --resource-group $rg --name $app --type console --tail 50
```

참가자가 검토한 통합 검사를 직접 실행합니다. 로그 해석이 필요하면 Copilot app 채팅에 비밀을 제거한 결과와 다음 요청을 전달합니다.

```text
전달한 azd 출력과 통합 검사 결과를 검토해 줘. 구독이나 환경을 바꾸지 마.
.NET 10 Linux 이미지 tag/digest, 비루트 실행, 포트 8080과 readiness의 근거를 확인해 줘.
Azure SQL 관리 ID/쿼리, Service Bus 처리, private Blob과 Data Protection 검사의
누락을 찾아 줘. 통과/실패/미실행을 구분하고 추가 검사 명령은 제시만 해 줘.
데이터 삭제, 방화벽 전체 개방이나 역할 범위 확대는 하지 마.
오류는 비밀을 제거한 로그와 원인을 제시하고 필요한 변경 승인을 기다려 줘.
```

코드 수정이 필요하면 별도의 제한된 복구 계획을 검토한 뒤 실행합니다.

`azd show`의 URL을 열어 원본과 같은 가짜 데이터로 학생/강좌/강사/학과, 검색/페이지 이동과 통계를 확인합니다. 실습 1에서 기록한 강좌 이미지 업로드와 조회, 개체 변경 후 알림도 다시 확인합니다. 비동기 메시지가 처리되지 않았는데 HTTP 응답만 성공한 것은 완료가 아닙니다.

새 revision에서도 파일과 Data Protection 키를 재사용하는지 확인합니다. 다중 replica를 추가하지 않아도 재배포에 따른 키 손실을 확인할 수 있습니다. 원본 UI의 인증/쿠키가 있는 경우 세션 동작도 비교합니다.

## 완료 기준과 문제 해결

정상 revision과 실제 데이터/메시지/파일 동작이 확인되면 이미지 식별자와 검증 결과를 기록합니다. Windows 실행 성공만으로 Linux 성공을 주장하지 않습니다. 인증, 포트, DB 또는 키 저장 오류는 [문제 해결](08-troubleshooting.md)을 참고하고, 실패한 배포도 [정리](07-cleanup.md)를 수행합니다.
