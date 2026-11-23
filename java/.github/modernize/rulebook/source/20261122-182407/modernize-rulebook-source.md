# Java ACA 워크숍 현대화 기준

- 현재 승인한 계획의 작업 범위만 수행한다. 설치와 외부 서비스 사용은 별도로 승인받는다.
- Java 8에서 정식 JDK 25로 업그레이드한다. EA 버전은 사용하지 않는다.
- Spring Boot 4.1.2를 기준으로 JDK 25와 라이브러리의 호환성 및 지원 조건을 확인한다.
  다른 안정 버전이 필요하면 근거를 제시하고 변경 승인을 받는다. 유료 지원이나 저장소를 전제하지 않는다.
- web과 worker, 기존 화면, 업로드, 파일 조회와 비동기 썸네일 동작을 유지한다.
  불필요한 프런트엔드 재작성은 하지 않는다.
- dev 프로필의 업로드는 DB에 메타데이터를 기록하지 않는다. dev 프로필을 사용하지 않는
  S3 처리 경로의 DB 기록과 조회는 별도 이전 대상이다. 로컬에서 확인한 원본 기능과 구분한다.
- PostgreSQL은 Azure Database for PostgreSQL Flexible Server로,
  RabbitMQ는 Service Bus로, 로컬 파일과 S3는 비공개 Blob으로 이전한다.
- 관리 ID, 최소 권한, TLS를 사용한다. 비밀정보는 코드, 설정과 Git에 저장하지 않는다.
  DB 내부의 보안 주체(principal)와 권한은 ARM 역할과 구분한다. 이전 작업을 수행할 계정도 별도로 정한다.
- 메시지 중복 수신, 재시도, dead-letter와 종료 시 처리 동작을 유지한다. Blob을 공개하거나
  무기한 SAS URL로 우회하지 않는다. S3 데이터 이전과 AWS 접근은 별도로 승인받는다.
- 최종 환경은 Linux Azure Container Apps이다. AKS나 App Service는 사용하지 않는다.
- azd, Bicep과 로컬 컨테이너 엔진을 사용한다. 원격 빌드, ACR Tasks, az acr build는 금지한다.
- Windows는 PowerShell 7에서 `. ../scripts/use-java.ps1 -Jdk 8` 또는 `-Jdk 25`를,
  macOS/Linux는 `source ../scripts/use-java.sh --jdk 8` 또는 `--jdk 25`로 JDK를 먼저 선택한다.
  같은 셸에서 Maven Wrapper를 사용하고 버전, 종료 코드와 실제 테스트 수를 기록한다.
- 하나의 계획에 기준 테스트, 업그레이드, Azure 코드, azd 산출물을 순서대로 포함한다.
  변경할 파일, 버전 선택 근거, 검증 명령과 중단 및 복구 기준을 명시한다.
- Azure 리소스 생성, DB 변경과 데이터 이전, 이미지 게시, 배포와 삭제는
  계획 실행에 포함하지 않는다. 참가자가 별도 승인 후 직접 실행한다.
- 테스트를 삭제하거나 건너뛰고 성공한 것으로 처리하지 않는다. 실제 실행 결과와 실행하지 않은 통합 테스트를 구분한다.
