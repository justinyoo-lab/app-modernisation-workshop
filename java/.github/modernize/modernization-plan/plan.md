# 현대화 계획: modernization-plan

**프로젝트**: assets-manager (Java web 및 worker)

## 기술 구성

- **언어**: Java 8 → 정식 JDK 25
- **프레임워크**: Spring Boot 2.7.18 → Spring Boot 4.1.2; Spring Framework 버전은 선택한 Boot 릴리스에서 관리
- **빌드 도구**: Maven Wrapper
- **데이터베이스**: PostgreSQL → Azure Database for PostgreSQL Flexible Server
- **메시징**: RabbitMQ → Azure Service Bus
- **저장소**: dev 로컬 파일과 AWS S3 → 비공개 Azure Blob Storage

## 개요

기존 web과 worker를 Linux Azure Container Apps 대상으로 현대화하되 화면, 업로드, 파일 조회, 비동기 썸네일 처리와 프로필별 동작을 유지합니다. Java 8 기준선 테스트, 런타임/프레임워크 업그레이드, Azure 서비스 연동 코드와 테스트, 배포 산출물 순서로 진행합니다. 각 단계가 검증을 통과해야 다음 단계로 넘어갑니다.

dev 프로필은 계속 파일을 저장하되 이미지 메타데이터를 DB에 기록하지 않아야 합니다. dev가 아닌 S3 처리 경로는 기존처럼 메타데이터와 썸네일 메타데이터를 기록하고 조회해야 합니다. 두 저장 경로를 비공개 Blob으로 옮기되 Blob을 공개하거나 무기한 SAS URL에 의존하지 않습니다. 메시지 중복 수신, 재시도, dead-letter, 확인 응답과 종료 동작도 유지합니다.

## 마이그레이션 영향 요약

| 애플리케이션 | 기존 구성 요소 | Azure 대상 | 인증 | 참고 |
|---|---|---|---|---|
| web | Java 8 / Boot 2.7 | Linux Container Apps | 관리 ID | 기존 화면과 업로드/조회 유지 |
| worker | Java 8 / Boot 2.7 | Linux Container Apps | 관리 ID | 비동기 썸네일 처리 유지 |
| web, worker | PostgreSQL | PostgreSQL Flexible Server | 관리 ID | DB 주체 권한과 ARM 역할을 구분 |
| web, worker | RabbitMQ | Azure Service Bus | 관리 ID | 재시도, 중복, dead-letter, 종료 동작 유지 |
| web, worker | 로컬 파일 / S3 | 비공개 Blob Storage | 관리 ID | dev와 비-dev 메타데이터 동작 구분 |

## 버전 및 호환성 근거

- 정식 JDK 25는 규칙집에서 요구하는 대상 버전입니다. EA 빌드는 허용하지 않습니다.
- Spring Boot 4.1.2는 규칙집 기준이며 이 계획에 포함하기로 확인했습니다. JDK 25 및 Spring Boot 4.1.2에 대해 Spring Framework, Jakarta 네임스페이스, Maven 플러그인과 직접/전이 라이브러리의 호환성을 검증합니다. 지원되는 릴리스와 BOM 근거로 호환되는 정식 라이브러리 버전을 선택하고, 유료 지원이나 비공개 저장소를 전제하지 않습니다.
- Boot 4.1.2 또는 필수 라이브러리의 호환성/가용성을 확인할 수 없으면 버전을 변경하기 전에 중단하고 다른 정식 버전 사용에 대한 승인을 요청합니다. 호환성 오류를 우회하거나 버전을 임의로 낮추지 않습니다.
- 각 단계 전에 같은 셸에서 JDK를 선택하고 Maven Wrapper를 사용합니다.

  ```powershell
  . ..\scripts\use-java.ps1 -Jdk 8
  .\mvnw.cmd test
  . ..\scripts\use-java.ps1 -Jdk 25
  .\mvnw.cmd test
  ```

  ```bash
  source ../scripts/use-java.sh --jdk 8
  ./mvnw test
  source ../scripts/use-java.sh --jdk 25
  ./mvnw test
  ```

  각 실행의 Java 버전, 종료 코드와 실제 테스트 수를 기록합니다. 테스트를 삭제하거나 건너뛰지 않으며 건너뛴 테스트를 통과로 계산하지 않습니다.

## 변경 대상 파일

| 단계 | 예상 파일 및 산출물 |
|---|---|
| Java 8 기준선 및 런타임/프레임워크 업그레이드 | `pom.xml`, `web/pom.xml`, `worker/pom.xml`, web/worker 테스트와 관련 애플리케이션 소스 |
| Web 서비스 코드 | `web/src/main/java/com/microsoft/migration/assets/config/{AwsS3Config,RabbitConfig}.java`; `service/{AwsS3Service,LocalFileStorageService,StorageService}.java`; `model/{ImageMetadata,ImageProcessingMessage}.java`; `repository/ImageMetadataRepository.java`; `src/main/resources/application.properties` |
| Worker 서비스 코드 | `worker/src/main/java/com/microsoft/migration/assets/worker/config/{AwsS3Config,RabbitConfig}.java`; `service/{AbstractFileProcessingService,FileProcessor,LocalFileProcessingService,S3FileProcessingService}.java`; `model/{ImageMetadata,ImageProcessingMessage}.java`; `repository/ImageMetadataRepository.java`; `src/main/resources/application.properties` |
| 기준선 및 서비스 테스트 | web에 새 테스트 추가; `worker/src/test/java/com/microsoft/migration/assets/worker/service/{LocalFileProcessingServiceTest,S3FileProcessingServiceTest}.java` 보강 |
| 인프라 및 DB 준비 | 루트 `azure.yaml`, `infra/main.bicep`, 별도 `infra/database/init.sql` 및 실행 안내 |
| 컨테이너 산출물 | `web/Dockerfile`, `worker/Dockerfile`; 로컬 컨테이너 엔진으로만 이미지 빌드 |

작업별 세부 범위, 평가 이슈 매핑과 의존성은 `.metadata/tasks.json`에 있습니다.

## 검증 게이트, 중단 및 복구 기준

1. 업그레이드 전에 Java 8 기준선을 만들고 검증합니다. 기준선 검증이 실패하면 원인을 파악하고 재현 가능하게 고칠 때까지 후속 작업을 시작하지 않습니다.
2. 업그레이드, 서비스 이전, 인프라 산출물, 통합 테스트, 보안, 컨테이너 산출물 각 단계의 빌드/테스트가 실패하면 의존 작업을 중단합니다. 실패 출력을 보존하고 해당 단계를 성공으로 표시하지 않습니다.
3. 마지막으로 통과한 단계를 복구 기준으로 삼습니다. 실패 단계의 변경만 수정하거나 되돌린 뒤 해당 검증을 다시 실행합니다. 통과한 경우에만 이어서 진행합니다. 버전이나 동작 변경으로 게이트를 통과할 수 없다면 테스트를 완화하지 말고 범위 결정을 요청합니다.
4. 통합 테스트는 모의 의존성만 사용합니다. 이 결과는 실제 Azure 리소스, 자격 증명, 네트워크 또는 서비스가 동작한다는 근거가 아닙니다.
5. 이 계획의 작업은 Azure 리소스 생성, 실제 DB 변경, DB/S3 데이터 이전, 이미지 게시, 배포와 리소스 삭제를 하지 않습니다. Bicep 작업의 `provision`은 `false`입니다.
6. 설치와 외부 서비스 사용에는 별도 승인이 필요합니다. 워크로드 관리 ID는 이후 이전/초기화 작업에 사용할 참가자/운영자 계정과 분리합니다. 별도 승인 작업 전에 운영자와 필요한 권한만 식별하며 자격 증명을 계획에 저장하지 않습니다.

## 별도 DB 초기화 및 참가자 azd 절차

DB 초기화는 검토 가능한 별도 절차와 SQL 산출물로 준비하되 계획 실행 중에는 수행하지 않습니다. 이 스크립트는 필요한 애플리케이션 스키마만 생성하고 데이터 이전은 하지 않아야 합니다. 실행할 운영자는 워크로드 관리 ID와 별도로 지정해야 합니다. DB 변경과 데이터 이전에는 참가자의 별도 승인이 필요합니다.

계획 완료 후 참가자는 산출물을 검토하고, 환경을 변경하는 단계마다 별도로 승인한 뒤 다음을 진행할 수 있습니다.

1. `azd auth login`으로 로그인하고 `azd env new <환경 이름>`으로 환경을 만들거나 선택합니다.
2. 생성된 Bicep과 환경 설정을 검토합니다. 승인한 뒤에만 `azd provision`을 실행합니다.
3. DB 초기화 절차를 별도로 승인하고 실행합니다. 기존 PostgreSQL 데이터 또는 S3 객체 이전은 각각 별도 승인 대상입니다.
4. 로컬 컨테이너 엔진으로 web/worker 이미지를 빌드하고 태그와 설정을 검토합니다.
5. 별도 승인 후에만 `azd deploy`로 이미지를 게시하고 애플리케이션을 배포합니다. 이 참가자 절차는 안내일 뿐 이 계획에서 실행하는 작업이 아닙니다.

## 미해결 질문 및 확인 사항

- [x] Q: JDK 25와 호환되지 않는 기존 Boot 2.7.18도 함께 업그레이드할까요? → A: 예. 규칙집 기준인 Spring Boot 4.1.2를 사용하고 라이브러리 호환성을 확인합니다.
- [x] Q: Azure 서비스 통합 테스트를 포함할까요? → A: 모의 의존성을 사용하는 테스트를 포함하고 실제 Azure 서비스에는 연결하지 않습니다.
- [x] Q: 인프라를 실제로 프로비저닝할까요? → A: 아니요. Bicep과 azd 산출물만 준비하고 인프라 작업의 `provision`은 `false`로 둡니다.
- [x] Q: 보안/CVE 검토와 수정 작업을 포함할까요? → A: 예. 평가 보고서의 자동 생성 이슈는 확정된 취약점으로 간주하기 전에 검증합니다.
- [x] Q: 배포 대상은 무엇인가요? → A: Linux Azure Container Apps입니다.
- [x] Q: 컨테이너화를 포함할까요? → A: 예. Container Apps에 필요한 산출물을 준비하고 로컬에서만 빌드하며 게시/배포하지 않습니다.
- [x] Q: 배포 작업을 계획에서 실행할까요? → A: 아니요. 실제 프로비저닝, 이미지 게시와 배포는 제외하고 참가자용 azd 절차만 문서화합니다.
