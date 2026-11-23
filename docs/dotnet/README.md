# .NET 트랙: Contoso University

[전체 목차](../../README.md) | [다음: 준비](00-setup.md) | [문제 해결](08-troubleshooting.md)

## 목표

Windows의 ASP.NET MVC 5/.NET Framework **`v4.8`** 앱을 .NET 10/ASP.NET Core로 바꾸고, Windows 전용 의존성을 제거해 **Linux ACA**에 배포합니다. 기존 화면과 학생, 강좌, 강사, 학과 관리 기능을 보존합니다.

## 순서

| 순서 | 실습 | 완료 시 확인할 것 |
| --- | --- | --- |
| 0 | [준비](00-setup.md) | 저장소 생성과 클론, 사전 점검과 보완, Modernize CLI 준비 및 샘플 다운로드 |
| 1 | [원본 로컬 실행](01-run-locally.md) | IIS Express, LocalDB, MSMQ와 주요 화면 동작, 워크숍 저장소 기준선 커밋 |
| 2 | [평가와 계획](02-assess-and-plan.md) | 평가 결과, 제약조건, 실행 범위와 승인 계획 |
| 3 | [.NET 10 업그레이드](03-upgrade.md) | .NET 10/ASP.NET Core 전환과 회귀 검사 |
| 4 | [Azure 서비스 이전](04-migrate-azure-services.md) | Azure SQL, Service Bus, private Blob 연결과 Windows 전용 의존성 제거 |
| 5 | [azd 배포 준비](05-prepare-azd.md) | Dockerfile, azure.yaml, Bicep 및 비용/권한 검토 |
| 6 | [ACA 배포](06-deploy-aca.md) | 프로비저닝, 로컬 이미지 빌드, 배포, 실제 기능 확인 |
| 7 | [정리](07-cleanup.md) | Azure 리소스와 로컬 실습 프로세스 정리 |
| 8 | [문제 해결](08-troubleshooting.md) | 진행 중 발생한 오류의 원인과 조치 확인 |

> [!NOTE]
> **Windows 실행 환경**
>
> Copilot app에서 앱 폴더를 열고 Windows 터미널의 MSBuild와 IIS Express로 원본을 빌드하고 실행합니다. Visual Studio IDE를 열 필요는 없습니다.

각 실습의 완료 조건에 따라 실제 앱 동작을 확인하세요. 문제가 생기면 [문제 해결](08-troubleshooting.md)을 참고하세요.

Copilot app의 PowerShell 7 터미널에서 Modernize CLI로 평가하고 네 계획을 단계별로 검토합니다. 실제 Azure 배포와 정리는 참가자가 azd로 실행합니다.
