# Modernization Summary: 004-transform-rabbitmq-servicebus

## finalStatus
**success**

## successCriteriaStatus
- passBuild: true
- passUnitTests: true
- generateNewUnitTests: true

## Summary

Migrated the `web` and `worker` Maven modules from RabbitMQ (Spring AMQP) messaging to
Azure Service Bus with Azure Managed Identity authentication, following the
`migration-amqp-rabbitmq-servicebus` and `migration-mi-servicebus` skills, tempered by
the task's explicit least-privilege and behavior-preservation requirements. All work was
performed offline/mock only — no real Azure Service Bus namespace was provisioned or
contacted.

### Dependency changes
- Removed `spring-boot-starter-amqp` (and its transitive `com.rabbitmq:amqp-client`
  dependency) from `web/pom.xml` and `worker/pom.xml`. This fully remediates
  CVE-2026-69220, CVE-2026-69219, CVE-2026-63337, and CVE-2026-75516, all of which were
  verified (via `cve-assessment-result.json`) to originate from the transitive
  `amqp-client` dependency pulled in by the RabbitMQ starter.
- Added `com.azure.spring:spring-cloud-azure-starter` and
  `com.azure.spring:spring-messaging-azure-servicebus`. The root `pom.xml` already
  declared `spring-cloud-azure-dependencies` BOM v7.4.0 (compatible with Spring Boot
  4.1.2), so no BOM version change was required.

### Configuration changes
- Removed all `spring.rabbitmq.*` properties (host/port/username/password — the
  "Localhost Usage" assessment finding) from both modules' `application.properties`.
- Added Service Bus configuration using Azure Managed Identity:
  `spring.cloud.azure.credential.managed-identity-enabled=true`,
  `spring.cloud.azure.credential.client-id=${AZURE_MANAGED_IDENTITY_CLIENT_ID:}`,
  `spring.cloud.azure.servicebus.namespace=${SERVICE_BUS_NAMESPACE}`,
  `spring.cloud.azure.servicebus.entity-type=queue`.
- No connection strings, shared access keys, or other secrets were introduced anywhere
  in source, config, or Git history. The Service Bus Java SDK always connects over
  AMQP 1.0 transport wrapped in TLS (not configurable to plaintext), satisfying the TLS
  requirement.

### Code changes
- `AssetsManagerApplication` / `WorkerApplication`: `@EnableRabbit` → `@EnableAzureMessaging`.
- New `ServiceBusConfig` classes (replacing `RabbitConfig`) define the queue name
  constant and a `PropertiesSupplier<ConsumerIdentifier, ProcessorProperties>` bean with
  `autoComplete(false)`, preserving the original manual-acknowledgement semantics.
  **Deliberately no `ServiceBusAdministrationClient` / queue auto-provisioning bean was
  added**, even though the generic migration skill suggests one: provisioning queues at
  startup requires Service Bus "Owner"/management RBAC, which conflicts with the task's
  explicit "least-privilege sender/receiver permissions" requirement. The
  `image-processing` queue is assumed to be provisioned out-of-band by infrastructure;
  the application identity only needs Service Bus Data Sender (web producer) and/or Data
  Receiver (worker/backup consumers) roles.
- Producers (`AwsS3Service`, `LocalFileStorageService`): `RabbitTemplate.convertAndSend()`
  → `ServiceBusTemplate.send()` with `MessageBuilder.withPayload(...).build()`.
- Consumers (`AbstractFileProcessingService` in worker, `BackupMessageProcessor` in web):
  `@RabbitListener` + `Channel`/`@Header(DELIVERY_TAG)` manual ack →
  `@ServiceBusListener` + `@Header(RECEIVED_MESSAGE_CONTEXT) ServiceBusReceivedMessageContext`.
  Acknowledgement mapping was based on the original RabbitMQ `requeue` flag rather than a
  uniform rule, to precisely preserve documented behavior from the frozen baseline specs
  (`test-cases.md`):
  - `channel.basicAck()` → `context.complete()`
  - Worker `nack(tag, false, requeue=false)` (dead-letter path, matches baseline spec
    wording "routed to the dead-letter path") → `context.deadLetter()`
  - Web backup processor `nack(tag, false, requeue=true)` (immediate redelivery) →
    `context.abandon()`
  - Added null-context guards for graceful shutdown tolerance.
  - Catch blocks broadened from `IOException` to `Exception` since the Azure SDK throws
    unchecked exceptions where RabbitMQ's client threw checked `IOException`.
- Deleted `RabbitConfig.java` in both modules.

### New/updated tests (generateNewUnitTests=true)
- `AwsS3ServiceMessagingTest`, `LocalFileStorageServiceMessagingTest` (web, producer
  side): success and duplicate-send paths.
- `BackupMessageProcessorTest` (web, consumer side): success (complete), retry
  (ack failure → abandon), duplicate delivery, graceful shutdown.
- `AbstractFileProcessingServiceTest` (worker, consumer side): success (complete),
  duplicate delivery, dead-letter (failed download → deadLetter, no complete/abandon),
  graceful shutdown.
- `ServiceBusConfigurationTest` (web and worker): verifies no `spring.rabbitmq.*`
  remains, no connection-string/secret/password literals in servicebus/jms properties,
  managed identity enabled, and namespace externalized via environment variable
  placeholders.

### Consistency check
Ran `validation-check-consistency` against the migration diff. Result: **no Critical or
Major issues found**. The report confirmed functional equivalence of the ack/nack →
complete/abandon/deadLetter mapping, correct dependency/annotation/template migration,
and no secrets introduced. Report saved at
`004-transform-rabbitmq-servicebus/consistency-check-report.json`.

### Completeness scan
Re-grepped both modules' `src/main` trees for `rabbitmq|amqp|RabbitTemplate|@RabbitListener|localhost`
post-migration. Only remaining matches are explanatory code comments describing the
*prior* RabbitMQ behavior being mirrored, and a comment noting the Service Bus SDK's
underlying AMQP/TLS transport — no actual RabbitMQ configuration, dependencies, or
connectivity remain. Local dev convenience scripts (`scripts/startapp.*`,
`scripts/stopapp.*`) and `README.md` architecture narrative were left untouched,
consistent with the precedent set by the prior task (003) for out-of-scope local
tooling/documentation.

### Build & test verification
- `mvnw clean test` (JDK 25) completed with exit code 0 across both modules.
- No Maven `[ERROR]` lines or JUnit failure/error summaries were present. Two
  application-level `ERROR`-severity log lines appear in the test output; these are
  expected `logger.error(...)` calls exercised intentionally by the retry and
  dead-letter negative-path tests, not test failures.

## failureReason
N/A — task completed successfully.
