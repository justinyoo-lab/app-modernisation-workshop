# GitHub Copilot app으로 앱 현대화하기

GitHub Copilot app과 Modernize CLI로 앱을 현대화한 뒤, Azure Developer CLI(azd)로 Azure에 배포하는 실습 워크숍입니다.

## 워크숍 구조

```text
.
├── README.md       # 워크숍 안내와 진행 순서
├── docs
│   ├── java        # Java 트랙 목차, 준비, 실습, 문제 해결
│   └── dotnet      # .NET 트랙 목차, 준비, 실습, 문제 해결
├── scripts         # 사전 점검, 설치, 샘플 다운로드 도우미
├── java            # 다운로드되는 Java 앱
└── dotnet          # 다운로드되는 .NET 앱
```

## 시작하기 전에

실습에 필요한 계정과 저장소를 준비합니다.

- Azure 구독. 없다면 [Azure 무료 구독](https://aka.ms/azure/free)을 직접 신청합니다. 무료 크레딧의 서비스, 리전, 쿼터 제한과 유료 전환 조건을 확인하세요.
- GitHub 계정과 유효한 [GitHub Copilot 라이선스](https://github.com/github-copilot/signup). 조직 정책에 따라 Modernize CLI와 모델 사용이 제한될 수 있습니다.
- 템플릿으로 저장소 만들기 [![GitHub에서 템플릿으로 저장소 만들기](https://img.shields.io/badge/GitHub-Create%20repository%20from%20template-2ea44f?style=flat&logo=github&logoColor=white)](https://github.com/new?template_name=app-modernisation-workshop&template_owner=devkimchi)

## 트랙 선택

| 항목 | [Java 트랙](docs/java/README.md) | [.NET 트랙](docs/dotnet/README.md) |
| --- | --- | --- |
| 참가자 환경 | Windows, macOS 또는 Linux 데스크톱(Ubuntu, Debian 계열 자동 설치 지원) | Windows |
| 원본 앱 | Asset Manager, Java 8, Spring Boot 2.7.18 | Contoso University, .NET Framework 4.8, ASP.NET MVC 5 |
| 업그레이드 목표 | Java 25, Spring Boot 4.1.2 | .NET 10, ASP.NET Core MVC |
| 서비스 이전 | PostgreSQL, RabbitMQ, 파일(`dev`: 로컬, 그 외: AWS S3) → Azure PostgreSQL, Service Bus, Blob | LocalDB, MSMQ, 파일 → Azure SQL, Service Bus, Blob |
| 배포 구성 | 웹 앱과 워커를 각각 Azure Container Apps에 배포 | 웹 앱을 배포하며, 처리기를 분리할지는 계획 단계에서 결정 |

## 워크숍 진행 순서

| 순서 | Java 트랙 | .NET 트랙 |
| --- | --- | --- |
| 0 | [준비](docs/java/00-setup.md) | [준비](docs/dotnet/00-setup.md) |
| 1 | [원본 로컬 실행](docs/java/01-run-locally.md) | [원본 로컬 실행](docs/dotnet/01-run-locally.md) |
| 2 | [평가와 계획](docs/java/02-assess-and-plan.md) | [평가와 계획](docs/dotnet/02-assess-and-plan.md) |
| 3 | [JDK 25 업그레이드](docs/java/03-upgrade.md) | [.NET 10 업그레이드](docs/dotnet/03-upgrade.md) |
| 4 | [Azure 서비스 이전](docs/java/04-migrate-azure-services.md) | [Azure 서비스 이전](docs/dotnet/04-migrate-azure-services.md) |
| 5 | [azd 배포 준비](docs/java/05-prepare-azd.md) | [azd 배포 준비](docs/dotnet/05-prepare-azd.md) |
| 6 | [ACA 배포](docs/java/06-deploy-aca.md) | [ACA 배포](docs/dotnet/06-deploy-aca.md) |
| 7 | [정리](docs/java/07-cleanup.md) | [정리](docs/dotnet/07-cleanup.md) |

## 원본 샘플

| 원본 | 다운로드할 커밋 | 가져올 폴더 |
| --- | --- | --- |
| [Java 샘플](https://github.com/Azure-Samples/java-migration-copilot-samples/tree/317d3bbfd61fb1e402bea61f90e385bec12f2070/asset-manager) | `317d3bbfd61fb1e402bea61f90e385bec12f2070` | `asset-manager` 내용 |
| [.NET 샘플](https://github.com/Azure-Samples/dotnet-migration-copilot-samples/tree/7c1bf47b7e2627fe5a1c764716638815d35e0282/ContosoUniversity) | `7c1bf47b7e2627fe5a1c764716638815d35e0282` | `ContosoUniversity` 내용 |

다운로드 스크립트는 원본 코드와 대상 프레임워크를 바꾸지 않고 출처를 `upstream-source.json`에 기록합니다. 원본 저장소의 루트에 라이선스와 고지가 있으면 `UPSTREAM-*` 이름으로 함께 보존합니다.

## 참고자료

- [Java 앱 현대화: GitHub Copilot modernization](https://learn.microsoft.com/azure/developer/java/migration/migrate-github-copilot-app-modernization-for-java)
- [.NET 앱 현대화: GitHub Copilot modernization](https://learn.microsoft.com/dotnet/core/porting/github-copilot-app-modernization/overview)
- [GitHub Copilot app 다운로드](https://gh.io/app)
- [Modernize CLI](https://github.com/microsoft/modernize-cli)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview)

## 라이선스

이 저장소의 원본 자료에는 [MIT 라이선스](LICENSE)가 적용됩니다. 다운로드하거나 포함한 제3자 샘플은 각 원본 저장소의 라이선스와 고지를 따르며, 이 저장소의 MIT 라이선스가 제3자 자료의 재배포 권한을 부여하지는 않습니다.
