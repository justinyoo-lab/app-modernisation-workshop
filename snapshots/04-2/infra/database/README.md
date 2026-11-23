# 데이터베이스 초기화

`principals.sql`과 `init.sql`은 검토용 파일입니다. 자동으로 실행되지 않으며 실제 DB에 적용하려면 별도 승인이 필요합니다.

운영자는 관리 ID 이름과 기존 역할을 확인한 뒤 `postgres` 데이터베이스에서 `principals.sql`을 실행합니다. 역할 생성은 중복 실행을 보장하지 않습니다. 그다음 애플리케이션 데이터베이스에서 `init.sql`을 실행해 테이블과 권한을 준비합니다. 두 파일의 관리 ID 이름 자리표시자를 각각 바꾸고 SQL 리터럴과 식별자를 올바르게 이스케이프하세요.

`init.sql`은 `image_metadata`와 `image_processing_outbox`를 정의합니다. web에는 두 테이블의 읽기·쓰기 권한을, worker에는 메타데이터의 읽기·수정 권한만 부여합니다. DB 운영자와 앱 관리 ID는 구분합니다. 앱의 `ddl-auto=validate`는 스키마를 확인할 뿐 변경하지 않습니다.

`CREATE TABLE IF NOT EXISTS`는 기존 테이블의 열을 변경하지 않습니다. 기존 DB가 있다면 `last_modified`와 아웃박스 스키마를 별도로 검토해야 합니다. 데이터 이전과 기존 DB 변경은 이 절차의 자동 실행 범위에 포함되지 않습니다.
