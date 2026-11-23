# Modernization Summary — 002-upgrade-jdk25-spring-boot-4

## finalStatus: success

## successCriteriaStatus
- passBuild: true
- generateNewUnitTests: false
- passUnitTests: true

## Summary

Upgraded the `assets-manager` Maven reactor (`web` + `worker`) from Java 8 /
Spring Boot 2.7.18 to stable **JDK 25.0.5.1 (Temurin, LTS, GA — not an EA
build)** and **Spring Boot 4.1.2**, run only after the Java 8 baseline
(`001-setup-java8-baseline`) had already passed.

### Version evidence gathered before changing anything
- `spring-boot-dependencies:4.1.2` BOM (Maven Central) confirms: Spring
  Framework `7.0.10`, Jakarta Persistence `3.2.0`, Jakarta Servlet `6.1.0`,
  Jakarta Annotation `3.0.0`, Spring AMQP `4.1.2`, PostgreSQL JDBC `42.7.14`,
  Lombok `1.18.48`, Thymeleaf `3.1.5.RELEASE`, Mockito `5.23.0`,
  JUnit Jupiter `6.0.3`, maven-compiler-plugin `3.15.0`.
- Public docs confirm Spring Boot 4.1 keeps a Java 17 floor and has
  first-class support for Java 25 (current LTS) — selecting stable JDK 25 is
  within the supported range, not a downgrade workaround.
- Lombok `1.18.48` (BOM-managed) supports JDK 25 (minimum required is
  `1.18.40`); confirmed via public compatibility notes.
- `software.amazon.awssdk:s3:2.25.13` (already pinned in `web`/`worker` poms)
  required no change — it is pure-Java/Jakarta-independent and compiled and
  ran cleanly under JDK 25 with Spring Boot 4 without modification; left
  as-is per "upgrade only what's necessary for compatibility."

### Changes made
- `pom.xml` (parent): `spring-boot-starter-parent` `2.7.18` → `4.1.2`;
  `java.version` property `8` → `25`. Added a `pluginManagement` entry for
  `maven-compiler-plugin` with an explicit `lombok` entry in
  `annotationProcessorPaths` (`${lombok.version}`, BOM-managed). This is
  required because JDK 23+ disables implicit classpath-based annotation
  processor discovery by default; without this, Lombok-generated
  getters/setters/`@Slf4j` loggers silently stopped being generated and the
  build failed to compile.
- `web/.../model/ImageMetadata.java`, `worker/.../model/ImageMetadata.java`:
  `javax.persistence.*` → `jakarta.persistence.*` (Jakarta EE 11 namespace
  required by Spring Framework 7 / Boot 4; `javax.persistence` no longer
  exists in the managed Hibernate/JPA artifacts).
- `web/.../service/LocalFileStorageService.java`,
  `worker/.../service/LocalFileProcessingService.java`:
  `javax.annotation.PostConstruct` → `jakarta.annotation.PostConstruct`.
- `web/.../config/WebMvcConfig.java`: `javax.servlet.http.*` →
  `jakarta.servlet.http.*`; replaced the already-deprecated
  `WebMvcConfigurerAdapter`/`HandlerInterceptorAdapter` base classes (removed
  in this Spring Framework generation) with the modern
  `WebMvcConfigurer`/`HandlerInterceptor` interfaces (default methods), with
  no behavior change — same resource-handler/interceptor registrations.
- `web/.../config/RabbitConfig.java`, `worker/.../config/RabbitConfig.java`:
  `org.springframework.boot.autoconfigure.amqp.SimpleRabbitListenerContainerFactoryConfigurer`
  → `org.springframework.boot.amqp.autoconfigure.SimpleRabbitListenerContainerFactoryConfigurer`
  (Spring Boot 4 modularized/moved this autoconfigure package; class and
  behavior are otherwise unchanged).
- No dependency versions were pinned/downgraded to work around errors; all
  resolved versions come from the Spring Boot 4.1.2 BOM.
- `java.annotation`/Jakarta Annotations gap (JDK 11+ removed
  `javax.annotation`) is now fully closed via the Jakarta Annotation API
  pulled in transitively by Spring Boot 4's web/data starters.

### Verification (JDK 25, Maven Wrapper, both modules)
```
. (JAVA_HOME = Eclipse Adoptium Temurin 25.0.5.1, GA/LTS, not EA)
.\mvnw.cmd -q clean test
```
| Item | Value |
|---|---|
| Java version selected | Temurin `25.0.5.1` (`openjdk version "25.0.5.1" 2026-11-17 LTS`) — stable GA build |
| Maven | Apache Maven 3.9.9 (wrapper) |
| Exit code | **0** |
| Actual tests run | **6** total (`worker` module: `LocalFileProcessingServiceTest` 2, `S3FileProcessingServiceTest` 4) — identical count to the Java 8 baseline |
| Failures / Errors / Skipped | **0 / 0 / 0** |
| `web` module | No test sources exist yet (same as baseline; frozen `test-cases.md` specs remain untouched and will be turned into executable tests in a later integration-test task, not this one) |

No tests were added, deleted, skipped, or weakened in this task; the frozen
baseline test specs under `web/src/test/test-cases/` and
`worker/src/test/test-cases/` were not modified. `generateNewUnitTests` is
`false` because this task's scope is the runtime/framework upgrade only — no
new unit tests were required or added here.

## Next step
Per the plan's gating rule, downstream task `003-transform-postgresql-flexible-server`
may now proceed since this upgrade's build and regression suite passed under
stable JDK 25 / Spring Boot 4.1.2.
