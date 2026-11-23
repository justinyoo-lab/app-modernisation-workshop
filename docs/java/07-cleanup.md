# 7. 리소스와 로컬 실행 정리하기

[전체 목차](../../README.md) | [Java 목차](README.md) | [이전: ACA 배포](06-deploy-aca.md) | [문제 해결](08-troubleshooting.md)

## 목표

실습을 마치지 못했더라도 실습에서 만든 유료 리소스와 로컬 실행 환경을 정리합니다.

## 실습 범위

참가자가 직접 이번 실습에서 만든 리소스와 실행한 프로세스를 정리합니다. 실습에서 만들지 않은 리소스는 변경하거나 삭제하지 않습니다.

## 실습 전 확인 사항

**삭제할 환경과 리소스가 본인 실습용인지 먼저 확인**합니다. Azure 리소스를 삭제하면 데이터를 복구하지 못할 수 있습니다. 필요한 실습용 테스트 결과만 기록하고 실제 데이터는 포함하지 않습니다.

Copilot app 터미널의 **앱 루트**에서 실행합니다. Windows는 PowerShell 7, macOS와 Linux는 Bash 또는 Zsh를 사용합니다.

## Azure 정리

각 명령을 실행한 뒤 성공 여부와 출력을 확인하고 다음 단계로 진행합니다. `<이번-실습-환경명>`은 실제 환경명으로 바꿉니다(예: `contoso-asset-manager`).

```bash
azd env list
```

이번 실습 환경이 없거나 명령이 실패하면 다른 환경을 대신 선택하지 않습니다. 리소스를 만들지 않았다면 Azure 정리를 건너뛰고 로컬 정리로 이동합니다. 프로비저닝에 실패해 리소스가 남았을 가능성이 있다면 Azure 포털에서 환경명, 태그와 활동 로그를 대조해 찾습니다.

```bash
azd env select "<이번-실습-환경명>"
```

선택이 실패하거나 대상이 불분명하면 중단합니다. 이전에 선택된 환경을 대신 사용하지 않습니다. 선택한 환경의 구독 ID와 Azure CLI 구독 ID를 각각 확인합니다.

```bash
azd env get-value AZURE_SUBSCRIPTION_ID
```

```bash
az account show --query "{name:name,id:id}" --output table
```

두 구독 중 하나라도 승인한 본인 실습 구독과 다르거나 값을 확인하지 못하면 중단합니다. 다음 명령으로 리소스 그룹을 확인합니다.

```bash
# zsh/bash
rg=$(azd env get-value AZURE_RESOURCE_GROUP) && \
  [ -n "$rg" ] && printf '리소스 그룹: %s\n' "$rg"
```

```powershell
# PowerShell
$rg = azd env get-value AZURE_RESOURCE_GROUP
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rg)) { throw '리소스 그룹을 확인하지 못했습니다. Azure 정리를 중단하세요.' }
$rg
```

명령이 실패하거나 값이 비어 있으면 중단합니다.

```bash
az group show --name "$rg" --query "{name:name,id:id,tags:tags}" --output json
az resource list --resource-group "$rg" --query "[].{name:name,type:type}" --output table
```

위 명령이 모두 성공하면 구독, 리소스 그룹과 리소스가 삭제를 승인한 본인 실습 대상인지 확인합니다. 공유 리소스, 다른 환경 또는 기존 서비스가 포함되어 있으면 실행하지 않습니다. 확인을 마친 경우에만 다음 명령을 실행하고, 삭제 확인 메시지를 읽고 직접 승인합니다.

```bash
azd down
```

> [!NOTE]
>
> `--force`는 삭제 확인을 생략하고, `--purge`는 일시 삭제되는 리소스를 영구 삭제합니다. 사용하려면 대상과 복구 가능성, 영향을 확인하고 별도로 승인합니다.

삭제가 끝난 후 리소스 그룹을 확인합니다.

```bash
az group exists --name "$rg"
```

새로 만든 전용 리소스 그룹이라면 최종적으로 `false`인지 확인합니다. 기존 그룹을 재사용했거나 `azd`가 일부 리소스를 보존했다면 남은 항목을 별도로 확인합니다. 프로비저닝에 실패해 환경 출력이 없다면 Azure 포털에서 확인하고 임의의 그룹을 삭제하지 않습니다.

별도로 만든 역할 할당과 네트워크 리소스도 확인합니다. 저장소의 데이터 보존 및 soft delete 정책과 비용도 살펴봅니다. 정리에 실패하면 남은 리소스 ID와 오류를 소유자에게 전달합니다. Azure 리소스를 정리하기 전에 `.azure`를 삭제하면 남은 리소스를 추적하기 어려워집니다.

## 로컬 정리

Modernize CLI가 실행 중이면 해당 작업을 정상 종료하고 마지막 변경과 커밋을 확인합니다. 별도 터미널에서 실행 중인 web과 worker는 각 터미널에서 `Ctrl+C`로 종료합니다. 원본 스크립트로 시작했다면 종료 스크립트를 읽고 이번 앱과 컨테이너만 대상으로 하는지 확인한 뒤 실행합니다.

```bash
# zsh/bash
./scripts/stopapp.sh
```

```powershell
# PowerShell
./scripts/stopapp.cmd
```

Windows에서는 앱이 종료된 후 Web Module과 Worker Module 창을 직접 닫습니다.

종료 스크립트가 이미 컨테이너를 정리했다면 아래 삭제 명령을 반복하지 않습니다. PID 파일이 없거나 프로세스가 남아 있다면 Windows의 `Get-CimInstance Win32_Process`, macOS와 Linux의 `ps`로 앱 경로와 PID를 대조합니다. 확인한 PID에만 `Stop-Process -Id <PID>` 또는 `kill <PID>`를 사용합니다. 프로세스 이름으로 모든 Java 프로세스를 한꺼번에 종료하지 않습니다.

원본 앱을 Docker로 실행했는지 확인한 뒤 컨테이너를 조회합니다. 다른 엔진을 사용했다면 [문제 해결의 정리 안내](08-troubleshooting.md#대체-엔진-설정)를 따릅니다.

```bash
docker inspect assets-postgres assets-rabbitmq
```

조회가 실패하거나 **이 실습에서 생성한 컨테이너인지 확인하지 못했다면** 중단합니다. 확인한 컨테이너만 정지합니다. 다음 단계에서 DB와 큐의 실습 데이터가 삭제됩니다.

```bash
docker stop assets-postgres assets-rabbitmq
```

정지가 성공했는지 확인한 뒤 해당 컨테이너를 삭제합니다.

```bash
docker rm assets-postgres assets-rabbitmq
```

엔진 전체에 적용되는 `system prune`이나 모든 볼륨 삭제, 엔진 가상 머신 삭제는 하지 않습니다. 내려받은 앱 폴더와 비교 기준으로 남긴 Git 커밋은 보존해도 됩니다. 스크립트는 이를 자동으로 삭제하지 않습니다.

## 완료 및 다음 단계

- [ ] Azure 유료 리소스를 삭제했거나 보존 대상과 비용 책임자를 확인했습니다.
- [ ] 실습 프로세스와 컨테이너를 정지했습니다.
- [ ] 로컬 설정과 로그에 민감한 값이 남지 않았는지 확인했습니다.

삭제 권한이나 잠금 때문에 실패하면 [8. 문제 해결](08-troubleshooting.md)을 참고합니다.

위 항목을 모두 마쳤다면 Java 실습을 마칩니다.
