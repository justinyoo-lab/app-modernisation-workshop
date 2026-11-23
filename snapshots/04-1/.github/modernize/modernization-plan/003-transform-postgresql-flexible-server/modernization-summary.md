# Modernization Summary: 003-transform-postgresql-flexible-server

## Final Status
**success**

## Success Criteria
- passBuild: true
- passUnitTests: true
- generateNewUnitTests: true

## Summary

Migrated the `web` and `worker` modules' PostgreSQL connectivity from a
local, password-authenticated PostgreSQL instance (`jdbc:postgresql://localhost:5432/assets_manager`,
hardcoded `postgres`/`postgres` credentials) to Azure Database for PostgreSQL
Flexible Server using Azure Managed Identity (passwordless) authentication
over TLS, per the `migration-mi-postgresql` skill.

### Dependency changes
- Root `pom.xml`: added a `spring-cloud-azure-dependencies` BOM import
  (`7.4.0`, compatible with the project's Spring Boot `4.1.2`) in
  `dependencyManagement`.
- `web/pom.xml` and `worker/pom.xml`: added
  `com.azure.spring:spring-cloud-azure-starter-jdbc-postgresql` for
  passwordless JDBC authentication, plus test-scoped `com.h2database:h2`
  and `org.springframework.boot:spring-boot-starter-data-jpa-test`
  (Spring Boot 4 moved `@DataJpaTest`/`@AutoConfigureTestDatabase` into this
  starter) to support new repository-facing unit tests without a live
  database.

### Configuration changes
- `web/src/main/resources/application.properties` and
  `worker/src/main/resources/application.properties`:
  - Replaced the hardcoded localhost JDBC URL/username/password with an
    environment-variable-driven URL targeting
    `${POSTGRESQL_SERVER}.postgres.database.azure.com` with `sslmode=require`,
    and `spring.datasource.username=${POSTGRESQL_USERNAME}` (no password
    property at all — the access token is retrieved automatically).
  - Added `spring.datasource.azure.passwordless-enabled=true`,
    `spring.cloud.azure.credential.managed-identity-enabled=true`, and an
    optional `spring.cloud.azure.credential.client-id` for user-assigned
    managed identities.
  - Added inline documentation covering system-assigned vs. user-assigned
    managed identity, service-principal fallback, and Azure sovereign cloud
    scope/authority-host configuration.
  - Documented that the application database principal
    (`POSTGRESQL_USERNAME`) is a least-privilege database-level principal,
    distinct from ARM/control-plane roles and from the operator identity
    that runs one-time provisioning/grant scripts (consistent with
    `scripts/deploy-to-azure.sh`/`.cmd`, which already provision the Flexible
    Server with Entra-only auth and wire a passwordless service-connector
    connection using these same property names).
  - No code changes were required in `ImageMetadata`/`ImageMetadataRepository`
    in either module — JPA entities, repository operations, and S3-path
    metadata fields (`s3Key`, `s3Url`, `thumbnailKey`, `thumbnailUrl`) are
    untouched and behave identically.

### New tests (generateNewUnitTests)
- `web`/`worker` `config/DataSourceConfigurationTest`: parses each module's
  production `application.properties` directly (not via Spring context) and
  asserts the datasource URL targets Azure PostgreSQL Flexible Server over
  TLS, no password is configured, passwordless/managed-identity flags are
  enabled, and the database username is externalized rather than hardcoded.
- `web`/`worker` `repository/ImageMetadataRepositoryTest`: `@DataJpaTest`
  (`Replace.ANY`) repository-facing tests backed only by an in-memory H2
  database (`src/test/resources/application.properties` overrides the
  datasource to H2 and disables managed identity/passwordless flags for the
  test context) verifying CRUD behavior, timestamp lifecycle
  (`@PrePersist`/`@PreUpdate`), and preservation of S3-path metadata fields.
  No test connects to a live database.

### Verification
- Full Maven build (`mvnw clean install`, JDK 25) succeeded: `BUILD SUCCESS`.
- All unit tests passed: 13 tests run (7 in `web`, includes 4 new
  config + 3 new repository tests; 6 in `worker`, includes 4 new config +
  3 new repository tests + existing worker service tests), 0 failures,
  0 errors, 0 skipped.
- Consistency check (`validation-check-consistency`) reported zero Critical
  and zero Major issues across all 12 changed/added files.
- No Rulebook Files were provided for this task (`none`).

### Scope notes
- Local developer convenience scripts (`scripts/startapp.sh/.cmd`,
  `scripts/stopapp.sh/.cmd`) that spin up a local Docker PostgreSQL
  container for local development were left unchanged — they are outside
  the "web/worker PostgreSQL connectivity" scope of this task and do not
  affect the application's runtime connectivity configuration.
  `scripts/deploy-to-azure.sh/.cmd` already provisioned an Entra-only
  Flexible Server and passwordless service-connector wiring consistent with
  this change; no modification was needed there.
- No live database was connected to or migrated as part of this task.
