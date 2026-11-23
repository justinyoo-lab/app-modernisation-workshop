# .NET 7. 리소스와 로컬 실행 정리하기

[전체 목차](../../README.md) | [.NET 목차](README.md) | [이전: ACA 배포](06-deploy-aca.md) | [문제 해결](08-troubleshooting.md)

## 목표와 시작 조건

배포 성공 여부와 관계없이 실습에서 만든 자원을 확인하고 정리합니다. 삭제할 환경, 리소스 그룹, DB와 큐가 **본인 실습 전용**인지 먼저 확인합니다. 공유 리소스가 있으면 삭제를 승인하지 마세요.

실행 위치는 Copilot app 터미널의 **앱 루트**, 셸은 **Windows PowerShell 7**입니다. 참가자가 직접 정리하며 Azure 삭제는 복구할 수 없는 데이터를 포함할 수 있습니다.

## Azure 정리

각 코드 블록을 실행한 뒤 성공 여부와 출력을 확인하고 다음 블록으로 진행합니다. 실제 환경명으로 `<이번-실습-환경명>`을 바꿉니다.

```powershell
azd env list
```

이번 실습 환경이 없거나 명령이 실패하면 다른 환경을 선택하지 않습니다. 리소스를 만들지 않았다면 Azure 정리를 건너뛰고 로컬 정리로 이동합니다. 프로비저닝 중 실패해 리소스가 남았을 가능성이 있다면 Azure Portal에서 정확한 환경명/태그/활동 로그로 찾습니다.

```powershell
azd env select "<이번-실습-환경명>"
```

선택이 실패하거나 대상이 불분명하면 중단합니다. 이전에 선택된 환경을 대신 사용하지 않습니다. 선택한 환경의 구독 ID와 Azure CLI 구독 ID를 각각 확인합니다.

```powershell
azd env get-value AZURE_SUBSCRIPTION_ID
```

```powershell
az account show --query "{name:name,id:id}" --output table
```

두 구독이 승인한 본인 실습 구독과 다르거나 값을 확인하지 못하면 중단합니다. 다음 명령으로 리소스 그룹을 확인합니다.

```powershell
$rg = azd env get-value AZURE_RESOURCE_GROUP
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rg)) { throw '리소스 그룹을 확인하지 못했습니다. Azure 정리를 중단하세요.' }
$rg
```

```powershell
az group show --name $rg --query "{name:name,id:id,tags:tags}" --output json
```

```powershell
az resource list --resource-group $rg --query "[].{name:name,type:type}" --output table
```

위 명령이 모두 성공했고 구독, 그룹과 리소스가 삭제를 승인한 본인 실습 대상인지 확인한 경우에만 다음 명령을 실행합니다. 공유 리소스, 다른 환경 또는 기존 서비스가 포함되어 있으면 실행하지 않습니다. 삭제 확인 메시지도 읽고 직접 승인합니다. `--force`/`--purge`를 기본으로 사용하지 않습니다.

```powershell
azd down
```

삭제가 끝난 후 확인합니다.

```powershell
az group exists --name $rg
```

이번에 새로 만든 전용 그룹이라면 최종적으로 `false`인지 확인합니다. 기존 그룹을 재사용했거나 일부 리소스를 보존했다면 남은 리소스와 비용을 별도로 확인합니다. 프로비저닝이 중단되어 출력 값이 없을 때는 Azure Portal에서 확인하고 임의의 그룹을 지우지 않습니다.

별도 역할 할당, 네트워크, Data Protection 키 저장소 및 soft-delete 보존도 확인합니다. 실패한 삭제를 성공으로 표시하지 말고 남은 ID와 오류를 기록합니다. Azure 정리가 끝나기 전 `.azure`를 먼저 지우지 않습니다.

## 로컬 정리

Modernize CLI가 실행 중이면 해당 작업을 정상 종료하고 마지막 변경과 커밋을 확인합니다. CLI 종료와 아래 앱 서버 종료는 별개입니다.

원본은 `run-dotnet-original.ps1 -Run`을 실행한 IIS Express 터미널에서 `Q` 또는 `Ctrl+C`로 종료합니다. Copilot app이 시작했다면 해당 장기 실행 터미널과 기록한 PID를 확인해 종료하도록 요청합니다. 선택적으로 IDE를 사용했다면 IDE 디버깅/실행을 중지합니다. 현대화 이후 `dotnet run`은 해당 터미널의 `Ctrl+C`로 종료합니다.

모든 `dotnet`/IIS Express 프로세스를 이름으로 일괄 종료하지 않습니다. 터미널이 없으면 먼저 프로세스 경로와 명령줄의 이번 앱 `.vs/workshop/applicationhost-<고유값>.config` 경로를 대조하고, 확인된 해당 PID에만 `Stop-Process -Id <PID>`를 사용합니다.

```powershell
Get-CimInstance Win32_Process -Filter "Name='iisexpress.exe'" |
    Select-Object ProcessId, ExecutablePath, CommandLine
```

관련 프로세스가 종료된 뒤 필요하면 이번 앱의 `.vs/workshop` 구성 파일만 지웁니다. 도우미는 실행마다 새 구성을 만들어 기존 IIS Express/IDE 설정을 덮어쓰지 않습니다. 생성 구성에는 로컬 절대 경로가 들어가므로 커밋하지 않습니다.

LocalDB 인스턴스, MSMQ 서비스, 개발 인증서는 다른 프로젝트가 사용할 수 있습니다. **서비스/기능 전체를 제거하지 않습니다.** 이 실습에서 만든 DB/큐와 데이터인지 원본 설정과 대조하고, 삭제가 필요한 경우 해당 DB/큐만 관리 도구에서 선택해 직접 삭제합니다.

실습에 사용한 Docker 이미지/컨테이너가 있으면 이름과 생성 시점을 확인해 개별 정리합니다. 다른 엔진을 사용했다면 [문제 해결의 정리 안내](08-troubleshooting.md#대체-엔진-설정)를 따릅니다. 전체 엔진 `system prune`, 모든 볼륨 또는 엔진 가상 머신 삭제는 하지 않습니다. 앱 폴더와 Git 기준선은 남겨도 됩니다.

## 완료 기준과 문제 해결

Azure 유료 리소스가 삭제되었거나 보존 대상/비용 책임자가 명확하고 실습 프로세스가 정지되어야 합니다. `.azure`, 로그와 로컬 사용자 비밀의 보관 범위를 확인하세요. 삭제 권한/잠금 문제는 [문제 해결](08-troubleshooting.md)을 참고합니다.
