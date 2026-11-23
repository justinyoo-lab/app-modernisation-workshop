# Infra Decision Table

> This document is part of the **frozen baseline bundle**. It records, for every external dependency the migrated application talks to, whether the post-migration tests will exercise it as a **real** provisioned resource, a **testcontainer**-backed emulator/dependency, or a **mock** at the SDK / HTTP boundary.

## Metadata

| Field | Value |
|-------|-------|
| Project | assets-manager (Java `web` module) |
| Module | `web` |
| Migration Scope | migrate from Java 8 / Spring Boot 2.7.18 / RabbitMQ / PostgreSQL (local) / local files & AWS S3 to Azure (JDK 25, Spring Boot 4.1.2, Azure Database for PostgreSQL Flexible Server, Azure Service Bus, private Azure Blob Storage), targeting Linux Azure Container Apps |
| Integration Test Environment | mock (set explicitly for this baseline task; every external dependency is mocked regardless of `infra/` content) |
| Created At | 2026-11-22 |
| `infra/` Snapshot | infra-missing (the repository's top-level `infra/` directory provisions the workshop *dev-box/workstation* used to run the lab, not the target application's Azure resources — no Blob Storage, Service Bus, or PostgreSQL Flexible Server endpoints/credentials are documented there for this app) |
| Status | baseline (frozen) |

## Decision Table

| Dependency | Infra Match | Decision | Auth Method | Reason |
|---|---|---|---|---|
| Local file system storage directory (NIO, `../storage`, used by `LocalFileStorageService` under profile `dev`) | No | mock | n/a | Integration Test Environment is `mock`; local filesystem access is isolated to an ephemeral test directory rather than the shared workshop `storage/` path. |
| AWS S3 object storage (`aws.s3.bucket`, used by `AwsS3Service` under profile `!dev`) | No | mock | n/a | `infra/` does not provision an application object-storage account/bucket; Integration Test Environment is `mock`, so the `S3Client` SDK boundary is mocked regardless. |
| RabbitMQ message broker (queue `image-processing`, used by `LocalFileStorageService`, `AwsS3Service`, `BackupMessageProcessor`) | No | mock | n/a | `infra/` does not provision an application message broker; Integration Test Environment is `mock`, so `RabbitTemplate`/listener container interactions are mocked at the AMQP client boundary. |
| PostgreSQL database (`image_metadata` table, used by `AwsS3Service` via `ImageMetadataRepository`, profile `!dev`) | No | mock | n/a | `infra/` does not provision an application PostgreSQL instance; Integration Test Environment is `mock`, so `ImageMetadataRepository` is mocked rather than backed by a real or containerized database. |

### Decision rules applied

Integration Test Environment = `mock` for this plan ⇒ every row's Decision is `mock` irrespective of `Infra Match`, per the explicit instruction to set every external dependency to mock for this baseline task.
