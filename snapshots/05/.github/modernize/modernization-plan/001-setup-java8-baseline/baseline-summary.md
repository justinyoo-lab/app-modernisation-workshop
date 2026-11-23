# Baseline Summary — 001-setup-java8-baseline

## Scope

Set up the frozen behavior baseline for the Java 8 / Spring Boot 2.7.18 `assets-manager` application (`web` + `worker` Maven modules) ahead of migrating to JDK 25 / Spring Boot 4.1.2 on Azure (Azure Database for PostgreSQL Flexible Server, Azure Service Bus, private Azure Blob Storage, Linux Azure Container Apps). No production source code was modified. Only baseline test artifacts were added under each module's `src/test/test-cases/`.

Assessment findings whose behavior is captured (not remediated) by this baseline: **File system - Java NIO**, **Local JDBC Calls**, **Localhost Usage**.

## Pre-change Snapshot (Java 8 baseline build)

Run from the `java/` project root, JDK selected via `. ../scripts/use-java.ps1 -Jdk 8` and built with the Maven Wrapper (`mvnw.cmd`), per the plan's prescribed baseline procedure.

| Item | Value |
|---|---|
| Java version selected | Temurin JDK **1.8.0_512** (`openjdk version "1.8.0_512"`, `javac 1.8.0_512`) |
| Maven | Apache Maven 3.9.9 (wrapper) |
| Command | `.\mvnw.cmd -q clean test` |
| Exit code | **0** |
| Actual tests run | **6** total (`worker` module only; `web` module had no test sources prior to this baseline) |
| Failures / Errors / Skipped | **0 / 0 / 0** |
| Per-class breakdown | `LocalFileProcessingServiceTest`: 2 tests, 0 failures. `S3FileProcessingServiceTest`: 4 tests, 0 failures. |

No tests were skipped or deleted; no skipped test was counted as passing. This snapshot reflects the pre-migration behavior baseline before any source changes are made in subsequent migration phases.

## Per-Module Scoping Decisions

| Module | In scope? | Reason |
|---|---|---|
| `web` | Yes | Directly touches all four migration-relevant resource types: local filesystem (NIO, `LocalFileStorageService`), AWS S3 (`AwsS3Service`), RabbitMQ (`RabbitTemplate`/`BackupMessageProcessor`), and PostgreSQL (`ImageMetadataRepository`, via `AwsS3Service`). |
| `worker` | Yes | Directly touches local filesystem (NIO, `LocalFileProcessingService`), AWS S3 (`S3FileProcessingService`), RabbitMQ (`AbstractFileProcessingService.processImage` listener), and PostgreSQL (`ImageMetadataRepository`, via `S3FileProcessingService`). |

Both modules of the two-module Maven reactor produce their own independent `test-cases.md` under their own `src/test/test-cases/`.

## Entry-Point Inventory (both modules)

### `web`

| Entry Point | Type |
|---|---|
| `GET /storage` | HTTP |
| `POST /storage/upload` | HTTP |
| `GET /storage/view-page/{key}` | HTTP |
| `GET /storage/view/{key}` | HTTP |
| `POST /storage/delete/{key}` | HTTP |
| Listener on queue `image-processing` (`BackupMessageProcessor`, profile `backup`) | Message-queue listener |

Excluded as trivial/non-migration-relevant: `GET /` (unconditional redirect, `HomeController`), `GET /storage/upload` (static form render, no data access) — see rationale recorded directly in `web/src/test/test-cases/test-cases.md`.

### `worker`

| Entry Point | Type |
|---|---|
| Listener on queue `image-processing` — local-storage processor (`LocalFileProcessingService`, profile `dev`) | Message-queue listener |
| Listener on queue `image-processing` — object-storage processor (`S3FileProcessingService`, profile `!dev`) | Message-queue listener |

## Existing Test Inventory and Conventions (Step 2)

| Module | Existing tests | Observation |
|---|---|---|
| `web` | none | No `web/src/test` tree existed prior to this baseline. |
| `worker` | `LocalFileProcessingServiceTest` (2 tests), `S3FileProcessingServiceTest` (4 tests) | Both exercise only internal helper methods (`generateThumbnail`, `downloadOriginal`, `uploadThumbnail`, `getStorageType`, `extractOriginalKey`) invoked from within `AbstractFileProcessingService.processImage`; neither constitutes end-to-end coverage of the listener entry point itself, so they do not satisfy the entry-point coverage gate and every worker test case in the frozen spec is new. |

**Extracted conventions** (binding for `verify-test-baseline`): JUnit 5, no AssertJ currently in use (plain `org.junit.jupiter.api.Assertions`); `@ExtendWith(MockitoExtension.class)` + `@Mock`/`@InjectMocks` for collaborator mocking; `org.springframework.test.util.ReflectionTestUtils` for private-field injection and private-method invocation; `@TempDir` for filesystem fixtures; test classes named `<Subject>Test`, one per production class under test; Arrange/Act/Assert comment structure in test bodies.

## Test Case Counts by Category

### `web` — `web/src/test/test-cases/test-cases.md` (18 new cases; 0 existing-covered)

| Category | Count |
|---|---|
| happy-path | 9 (TC-WEB-001, 002, 008, 009, 011, 012, 015, 016, 018) |
| boundary | 3 (TC-WEB-003, 004, 010) |
| special-input | 2 (TC-WEB-005, 006) |
| failure | 4 (TC-WEB-007, 013, 014, 017) |

(Authoritative, exact per-case category assignment is in `web/src/test/test-cases/test-cases.md`; this table is a rollup for convenience.)

### `worker` — `worker/src/test/test-cases/test-cases.md` (8 new cases; 0 existing-covered toward entry-point coverage)

| Category | Count |
|---|---|
| happy-path | 2 (TC-WKR-001, 002) |
| boundary | 2 (TC-WKR-003, 004) |
| special-input | 2 (TC-WKR-005, 006) |
| failure | 2 (TC-WKR-007, 008) |

## `testdata/` File List

### `web/src/test/test-cases/testdata/`

- `inputs/sample.jpg` (2,135 bytes — 300x200 opaque JPEG)
- `inputs/sample-portrait.png` (1,076 bytes — 150x300 PNG with alpha)
- `inputs/tiny.jpg` (633 bytes — 1x1 opaque JPEG)
- `inputs/oversized-10mb-plus.bin` (10,486,784 bytes — random bytes exceeding the 10MB multipart limit)
- `seed-data/image-metadata-seed.json` (3 representative `image_metadata` rows)

### `worker/src/test/test-cases/testdata/`

- `inputs/sample.jpg` (2,135 bytes — 300x200 opaque JPEG)
- `inputs/sample-portrait.png` (1,076 bytes — 150x300 PNG with alpha)
- `inputs/tiny.jpg` (633 bytes — 1x1 opaque JPEG)
- `inputs/corrupt.jpg` (74 bytes — plain text, not a decodable image, for the failure case)
- `seed-data/image-metadata-seed.json` (3 representative `image_metadata` rows, pre-thumbnail state)

## Infra Decision Table (Step 5)

Integration Test Environment confirmed as **mock** per the explicit task instruction ("set every external dependency to mock for this plan"). The repository's top-level `infra/` directory provisions the workshop dev-box/workstation only — it does not document any provisioned Blob Storage, Service Bus, or PostgreSQL Flexible Server endpoint for this application — so even under a `real`/`testcontainer` mode every row would have fallen back to `mock` (`infra-missing`). Full tables saved at:

- `web/src/test/test-cases/infra-decision-table.md` — Local file system (NIO), AWS S3, RabbitMQ, PostgreSQL → all `mock`, `n/a` auth.
- `worker/src/test/test-cases/infra-decision-table.md` — Local file system (NIO), AWS S3, RabbitMQ, PostgreSQL → all `mock`, `n/a` auth.

## Freeze Gate Validation (Step 6)

Both `test-cases.md` files were validated against the Required Field Checklist and Coverage Gate from the `create-test-baseline` skill:

- Every test case has a unique `TC-<MODULE>-NNN` ID, a valid `Category`, an exact `Entry Point`/`Entry Point Type`, a concrete `Trigger`, enumerated `Preconditions` (or `none`), an exact `Expected Response`, at least one `Resource Verification` bullet (or justified `none`), `Negative Verification` on every `failure`/skip case, and `Data References` that all resolve to files that exist under `testdata/`.
- Every entry point in both inventories has at least one `happy-path` case. Every entry point has at least one `failure` case, **except** `BackupMessageProcessor.processBackupMessage` in `web`, whose only externally reachable branch is a successful acknowledgment (documented rationale in the inventory section of `web/src/test/test-cases/test-cases.md`).
- No banned phrasing ("should return a reasonable error", "behaves as expected", "approximately N items", "etc.", un-named resource/state assertions) was found in either document.
- All seed/fixture records use 2–5 representative rows (3 used throughout).

**Checklist passed for both modules.**

## Freeze Declaration

`web/src/test/test-cases/` and `worker/src/test/test-cases/` (each containing `test-cases.md`, `infra-decision-table.md`, and `testdata/`) are declared **FROZEN** as of this run. No subsequent migration or verification phase may modify, rename, move, or delete anything inside either folder; any required change forces a re-freeze cycle (unfreeze → amend → re-validate → re-freeze).
