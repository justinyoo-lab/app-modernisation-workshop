# 1. 원본 앱을 로컬에서 실행하기

[전체 목차](../../README.md) | [Java 목차](README.md) | [이전: 준비](00-setup.md) | [다음: 평가와 계획](02-assess-and-plan.md) | [문제 해결](08-troubleshooting.md)

## 목표

Java 8 기반의 원본 앱을 빌드하고 이미지 업로드와 비동기 썸네일 생성을 확인합니다. 업그레이드 후에는 이 결과를 기준으로 앱의 동작을 비교합니다.

## 사전 준비

앞 단계에서 사용한 Copilot app 세션의 터미널에서 **앱 루트**(`java` 디렉토리)로 이동합니다.

```bash
cd java
```

앱 루트에 `pom.xml`, `web`, `worker`, `mvnw`, `mvnw.cmd`, `.mvn`이 있는지 확인합니다.

```bash
# zsh/bash
ls -al
```

```powershell
# PowerShell
dir
```

현재 Git 브랜치와 파일 변경 사항을 확인합니다.

```bash
git branch --show-current
git status --short
```

## JDK 8 선택과 원본 빌드

JDK 8을 선택한 뒤 빌드가 정상적으로 완료되는지 확인합니다.

```bash
# zsh/bash
source ../scripts/use-java.sh --jdk 8
./mvnw -version
./mvnw clean verify
```

```powershell
# PowerShell
. ../scripts/use-java.ps1 -Jdk 8
./mvnw.cmd -version
./mvnw.cmd clean verify
```

직접 명령을 실행하는 대신 Copilot app 채팅에 다음과 같이 빌드를 요청해도 됩니다.

```text
이 세션의 `java` 앱 루트에서 원본 앱을 빌드해 줘.
소스나 런타임은 바꾸지 마.
JDK 8을 먼저 선택하고 `mvnw`로 빌드해 줘.
같은 셸에서 버전 정보와 clean verify 실행 결과를 기록해 줘.
빌드 중 문제가 생기면 임의로 수정하지 말고, 수정 전에 별도로 승인을 받아 줘.
설치가 필요할 때도 별도로 승인을 받아 줘.
```

## 로컬 서비스와 앱 실행

```bash
# zsh/bash
./scripts/startapp.sh
```

```powershell
# PowerShell
./scripts/startapp.cmd
```

## 현재 앱의 동작 확인

브라우저에서 `http://localhost:8080`을 열고 다음을 확인합니다.

- 개인 정보가 없는 PNG 파일을 업로드하고 원본과 썸네일이 화면에 표시되는지 확인합니다.
- RabbitMQ 관리 화면 `http://localhost:15672`에서 로컬 데모 계정 `guest`/`guest`로 로그인합니다. **Queues and Streams**의 `image-processing` 큐에서 Ready, Unacked, Consumers를 확인합니다.
- Ready가 0인 것만으로 처리가 성공했다고 판단하지 않습니다. worker의 `Successfully generated thumbnail` 로그와 실제 썸네일을 함께 확인합니다.
- web 로그에서 `HikariPool-1 - Start completed` 메시지와 그 이후에 발생한 오류를 확인합니다. 앱을 시작할 때 DB에 연결됐더라도 이후 연결 상태는 달라질 수 있습니다.
- `dev` 프로필에서는 이미지를 업로드해도 DB에 메타데이터를 기록하지 않습니다. 화면에 이미지가 표시되고 `storage`에 파일이 저장되더라도 DB에 메타데이터가 없는 것이 정상입니다. `dev` 프로필을 사용하지 않는 S3 처리 경로의 메타데이터는 다음 평가 단계에서 따로 확인합니다.

macOS와 Linux에서는 앱 루트에 있는 로그 파일을 확인합니다.

```bash
# zsh/bash
tail -n 100 logs/worker.log
grep -n -F 'HikariPool-1 - Start completed' logs/web.log
grep -inE -C 3 'error|exception|connection refused|connection timed out' logs/web.log
```

Windows에서는 시작 스크립트가 띄운 창에서 로그를 확인합니다. 로그를 파일로 따로 저장했다면 다음 명령의 경로를 해당 파일 경로로 바꿔 실행합니다.

```powershell
# PowerShell
Get-Content "<worker-로그-경로>" -Tail 100
Select-String -Path "<web-로그-경로>" -SimpleMatch 'HikariPool-1 - Start completed'
Select-String -Path "<web-로그-경로>" -Pattern 'error|exception|connection refused|connection timed out' -Context 3,3
```

홈 화면이나 업로드 완료 메시지만으로 비동기 처리가 끝났다고 판단하지 않습니다. DB 또는 worker에서 오류가 발생하면 해결한 뒤 다시 확인합니다.

## 로컬 앱 종료

**앱 루트**에서 해당 종료 스크립트를 실행합니다.

```bash
# zsh/bash
./scripts/stopapp.sh
```

```powershell
# PowerShell
./scripts/stopapp.cmd
```

## 원본 앱 상태 커밋

개인 실습용으로 복제한 저장소에 원본 앱의 상태를 커밋으로 남깁니다. 기존 `.gitignore` 규칙을 유지하고 빌드 결과물과 비밀정보를 커밋 대상에서 제외합니다. `local.storage.directory`를 바꿨다면 해당 경로도 제외합니다.

```bash
# zsh/bash
printf '\n.azure/\nlogs/\npids/\n/storage/\n**/target/\n**/uploads/\n.env\n.env.*\n' >> .gitignore
```

```powershell
# PowerShell
Add-Content ./.gitignore "`n.azure/`nlogs/`npids/`n/storage/`n**/target/`n**/uploads/`n.env`n.env.*"
```

앱 루트에서 `git add .`를 실행한 뒤 커밋에 포함될 변경 사항을 모두 검토합니다.

```bash
git status --short
git add .
git diff --cached --stat
git diff --cached
```

업로드한 파일, 로그, 토큰이나 비밀정보가 담긴 연결 설정은 커밋 대상에서 제외합니다. 다시 검토해 문제가 없을 때만 커밋합니다.

```bash
git commit -m "Baseline: verified Java 8 sample"
```

Git 커밋 작성자 정보가 설정되어 있지 않다면 이 저장소에서만 사용할 이름과 이메일을 설정한 뒤 다시 커밋합니다.

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
```

## 완료 및 다음 단계

- [ ] Java 8 빌드를 마쳤습니다.
- [ ] web/worker 실행을 확인했습니다.
- [ ] PostgreSQL/RabbitMQ 연결을 확인했습니다.
- [ ] 이미지 업로드와 썸네일 생성을 확인했습니다.
- [ ] 원본 앱의 상태를 커밋으로 남겼습니다.

위 항목을 모두 마쳤다면 다음 단계인 [2. 평가하고 계획 승인하기](02-assess-and-plan.md)로 이동합니다.
