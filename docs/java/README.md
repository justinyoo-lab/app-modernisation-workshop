# Java 트랙: Asset Manager

[전체 목차](../../README.md) | [다음: 준비](00-setup.md) | [문제 해결](08-troubleshooting.md)

## 목표

Java 8/Spring Boot 2.7.18 앱을 **JDK 25**로 업그레이드하고 Azure 서비스와 연동합니다. 이후 web과 worker를 ACA에 배포합니다. 두 모듈의 구조와 기존 사용자 기능은 유지합니다.

## 순서

| 순서 | 실습 | 완료 시 확인할 것 |
| --- | --- | --- |
| 0 | [준비](00-setup.md) | 저장소 생성과 복제, 사전 점검과 보완, Modernize CLI 준비 및 샘플 다운로드 |
| 1 | [원본 로컬 실행](01-run-locally.md) | Java 8 앱의 화면, DB 연결, 큐와 worker 동작 확인 및 원본 상태 커밋 |
| 2 | [평가와 계획](02-assess-and-plan.md) | 평가 결과, rulebook, 단일 현대화 계획 |
| 3 | [JDK 25 업그레이드](03-upgrade.md) | JDK 25 빌드와 기존 기능의 회귀 테스트 |
| 4 | [Azure 서비스 이전](04-migrate-azure-services.md) | PostgreSQL, Service Bus, 비공개 Blob 연동 코드와 단위 테스트 |
| 5 | [azd 배포 준비](05-prepare-azd.md) | Dockerfile, `azure.yaml`, Bicep 및 비용과 권한 검토 |
| 6 | [ACA 배포](06-deploy-aca.md) | 프로비저닝, 로컬 이미지 빌드, 배포, 실제 기능 확인 |
| 7 | [정리](07-cleanup.md) | Azure 리소스와 로컬 실습 프로세스 정리 |
| 8 | [문제 해결](08-troubleshooting.md) | 진행 중 발생한 오류의 원인과 조치 확인 |

Windows는 PowerShell 7, macOS와 Linux 데스크톱은 Bash 또는 Zsh 터미널에서 진행합니다. `.sh` 파일을 직접 실행하면 Bash로 실행되며, macOS 기본 Bash 3.2도 지원합니다. JDK 선택 도우미만 현재 셸에서 `source` 또는 dot-sourcing으로 불러옵니다.

Copilot app 터미널에서 Modernize CLI로 앱을 평가하고 하나의 현대화 계획을 작성합니다. CLI 화면에서 계획을 검토한 뒤 실행합니다. 실제 Azure 배포와 정리는 참가자가 azd로 직접 진행합니다.

각 실습의 완료 조건에 따라 실제 앱 동작을 확인하세요. 문제가 생기면 [문제 해결](08-troubleshooting.md)을 참고하세요.
