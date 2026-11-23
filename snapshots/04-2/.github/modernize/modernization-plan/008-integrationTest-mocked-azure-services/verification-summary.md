# Post-Migration Verification Summary

> Task: `008-integrationTest-mocked-azure-services` — Phase 3 ("Verify the Migration") of the
> `verify-test-baseline` skill, covering both in-scope modules (`web`, `worker`) of the
> `assets-manager` application. This is the single report artifact for this task (per Step 9).
> Planning table / trigger audit: `post-migration-plan.md` (same folder). Per-module detailed
> findings authored by the two sub-agents that generated the tests are preserved verbatim in
> `verification-summary-web.md` / `verification-summary-worker.md` (same folder) and are
> incorporated/independently re-verified below.

## Scope

- Migration scope: Java 8 / Spring Boot 2.7.18 / RabbitMQ / local PostgreSQL / local files & AWS S3
  → stable JDK 25 / Spring Boot 4.1.2 / Azure Service Bus / Azure Database for PostgreSQL Flexible
  Server (managed identity) / private Azure Blob Storage (managed identity), targeting Linux Azure
  Container Apps.
- Both `web` and `worker` modules have a frozen `test-cases/` bundle (`test-cases.md`,
  `infra-decision-table.md`, `testdata/`) produced in task 001 (Phase 1 baseline). Both bundles'
  `infra-decision-table.md` set **every** external dependency (local/blob storage, Service Bus,
  PostgreSQL) to **mock**, per the explicit instruction for this task ("mock all external services;
  do not use Azure credentials, live endpoints, or provisioned resources"). No testcontainer, no
  real Azure resource, and no Azure credentials were used anywhere in this verification.
- Frozen spec integrity (Step 1): `test-cases.md`, `infra-decision-table.md`, and `testdata/` under
  both modules were read but **not** modified by this task.

## Runtime Execution Evidence (independently re-run and confirmed by the orchestrating session)

**Commands (run from repo root `java/`, JDK 25 on PATH/JAVA_HOME):**

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-25.0.5.10002-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
.\mvnw.cmd -pl web    -am verify "-Dit.test=*PostMigrationIT" "-Dsurefire.skip=true"
.\mvnw.cmd -pl worker -am verify "-Dit.test=*PostMigrationIT" "-Dsurefire.skip=true"
```

**web module (Failsafe, 4 `*PostMigrationIT` classes):**

```
Tests run: 18, Failures: 3, Errors: 0, Skipped: 0
```

**worker module (Failsafe, `WorkerMessageProcessingPostMigrationIT`):**

```
Tests run: 8, Failures: 5, Errors: 0, Skipped: 0
```

**Totals: 26 of 26 planned `*PostMigrationIT` methods executed == 26 `TC-*` planned in Step 4
(18 TC-WEB-* + 8 TC-WKR-*), 1:1, no extras/missing. 18 passed, 8 failed, 0 errors, 0 skipped.**

Both module builds end in `BUILD FAILURE` because `maven-failsafe-plugin`'s `verify` goal fails the
build on any `*PostMigrationIT` failure — this is the correct, expected outcome given genuine
failures were found; it is not a tooling/environment problem. (Note for operators: this environment's
default `JAVA_HOME` resolves to a bundled JDK 8 — `mvnw.cmd`/`mvn` must be invoked with `JAVA_HOME`
pointed at the installed `jdk-25.0.5.10002-hotspot` for the build to run at all, since the project
targets Java 25.)

Pre-existing unit tests (unchanged, not part of this task's output) continued to pass unaffected in
both modules: `web` 62/62, `worker` 51/51.

## Per-TC Breakdown

### web module (18 TC-WEB-*)

| TC ID | Result | Non-mock deps | Mock mechanism |
|---|---|---|---|
| TC-WEB-001 upload, dev happy path | PASS | none | `BlobContainerClient`/`BlobClient`/`ServiceBusTemplate` Mockito mocks via MockMvc |
| TC-WEB-002 upload, non-dev happy path | PASS | none | same + `ImageMetadataRepository` mock |
| TC-WEB-003 upload, empty file rejected | PASS | none | MockMvc, no SDK interaction expected/verified |
| TC-WEB-004 upload exceeds max size | **FAIL — Finding 3** | none | real over-the-wire HTTP (`TestRestTemplate`, `RANDOM_PORT`) |
| TC-WEB-005 upload path-traversal rejected | **FAIL — Finding 1** | none | MockMvc |
| TC-WEB-006 upload Unicode filename | PASS | none | MockMvc |
| TC-WEB-007 upload, queue unavailable | PASS | none | real over-the-wire HTTP; `ServiceBusTemplate.send` stubbed to throw |
| TC-WEB-008 list, dev happy path | PASS | none | `listBlobs()` stub |
| TC-WEB-009 list, non-dev happy path | PASS | none | `listBlobs()` + repository stub |
| TC-WEB-010 list, empty | PASS | none | empty `listBlobs()` stub |
| TC-WEB-011 view page happy path | PASS | none | `listBlobs()` stub |
| TC-WEB-012 view binary happy path | PASS | none | `BlobClient.downloadContent()` stub |
| TC-WEB-013 view page not found | PASS | none | empty `listBlobs()` stub |
| TC-WEB-014 view binary not found | PASS | none | `BlobClient.exists()=false` |
| TC-WEB-015 delete, non-dev happy path | PASS | none | repository + `BlobClient` stubs |
| TC-WEB-016 delete, dev happy path | PASS | none | `BlobClient.exists()=true` |
| TC-WEB-017 delete, not found | **FAIL — Finding 2** | none | `BlobClient.exists()=false` |
| TC-WEB-018 backup listener ack | PASS | none | real `BackupMessageProcessor` bean invoked directly (forced adaptation, see below), mocked `ServiceBusReceivedMessageContext` |

### worker module (8 TC-WKR-*)

| TC ID | Result | Non-mock deps | Mock mechanism |
|---|---|---|---|
| TC-WKR-001 process image, local happy path | **FAIL — Finding 5 (spec defect)** | none | real `BlobFileProcessingService` bean invoked directly (forced adaptation), `BlobContainerClient`/`BlobClient` mocks backed by real temp-file I/O |
| TC-WKR-002 process image, object-storage happy path | **FAIL — Finding 4** | none | real `AzureBlobFileProcessingService` bean invoked directly, mocks + `ImageMetadataRepository` mock seeded from JSON |
| TC-WKR-003 process image, local tiny not upscaled | PASS | none | same as TC-WKR-001 |
| TC-WKR-004 process image, object-storage portrait alpha | **FAIL — Finding 4** | none | same as TC-WKR-002 |
| TC-WKR-005 process image, local skips other storage type | PASS | none | same as TC-WKR-001 |
| TC-WKR-006 process image, object-storage Unicode key | **FAIL — Finding 4** | none | same as TC-WKR-002 |
| TC-WKR-007 process image, local source missing (dead-letter) | PASS | none | same as TC-WKR-001 |
| TC-WKR-008 process image, object-storage corrupt source (dead-letter) | **FAIL — Finding 4** | none | same as TC-WKR-002 |

For every one of the 26 TCs, all dependency rows (local/blob storage, message broker, PostgreSQL)
are `mock` per each module's `infra-decision-table.md`; `BlobContainerClient`/`BlobClient`,
`ServiceBusTemplate`, and `ImageMetadataRepository` are Mockito mocks for the full duration of every
test — no real or testcontainer-backed Azure Blob Storage, Service Bus, or PostgreSQL resource was
ever contacted, and no Azure credentials exist anywhere in the generated test sources (independently
confirmed by inspecting the generated `*PostMigrationIT.java` files and `application.properties`
test overrides).

## Findings (production bugs, platform-behavior changes, and spec defects — none patched around)

### Finding 1 — PRODUCTION BUG: dev-profile path-traversal rejection message text changed (TC-WEB-005)
- Expected (frozen spec): `Failed to upload file: Cannot store file with relative path outside current directory`
- Actual (observed): `Failed to upload file: Cannot access blob with relative path outside the container: ../tiny.jpg`
- Root cause: `BlobFileStorageService.uploadObject` now routes the filename through the new
  `BlobKeyValidator.sanitize(...)` helper, which throws a differently-worded `IOException`. The
  reject-the-upload *behavior* is correct and arguably more robust (CWE-22/23/36 hardening); only
  the externally-visible error-message *contract* regressed.

### Finding 2 — PRODUCTION BUG: delete-not-found rejection message text changed (TC-WEB-017)
- Expected (frozen spec): `Failed to delete file: File not found: does-not-exist.jpg`
- Actual (observed): `Failed to delete file: Blob not found: does-not-exist.jpg`
- Same class of regression as Finding 1 ("File not found" → "Blob not found").

### Finding 3 — PLATFORM-BEHAVIOR CHANGE: oversized upload now returns 413, not 500 (TC-WEB-004)
- Expected (frozen spec): `500 Internal Server Error`
- Actual (observed via real over-the-wire HTTP against a genuinely running embedded server):
  `413 Payload Too Large` / `CONTENT_TOO_LARGE`
- Root cause: Spring Framework 6.1+ (shipped with the Spring Boot 4.1.2 target of task 002) added
  built-in handling that maps `MaxUploadSizeExceededException` to 413 instead of letting it
  propagate uncaught to a generic 500, as the pre-migration Spring Framework version did. This is a
  genuine, framework-version-driven behavior change introduced by the JDK 25 / Spring Boot 4
  upgrade (task 002), not an application-code defect.

### Finding 4 — PRODUCTION BUG: worker's non-dev `storageType` literal regressed from `s3` to `azure-blob` (TC-WKR-002/004/006/008)
- The frozen spec's trigger body for these four object-storage-processor cases carries the literal
  `"storageType": "s3"` (the pre-migration AWS S3 convention). The migrated
  `AzureBlobFileProcessingService.getStorageType()` now returns `"azure-blob"`, confirmed changed
  from the pre-migration baseline's `"s3"` via git history.
- `AbstractFileProcessingService.processImage` only performs download/thumbnail/upload work when
  `message.getStorageType().equals(getStorageType())`; since `"s3" != "azure-blob"`, all four
  messages hit the storage-type-mismatch branch, which is silently treated as success
  (acknowledged, no file/DB work performed) instead of the happy-path/boundary/special-input/failure
  behavior the spec requires.
- **This breaks the frozen message contract** between any producer still emitting the
  `storageType: "s3"` convention (including, notably, the companion `web` module's own
  `AzureBlobService`, which emits its own `getStorageType()` value — confirmed consistent at
  `"azure-blob"` on the `web` side, so the live end-to-end `web`→`worker` path is internally
  self-consistent today) and any other/older message producer or in-flight queued message still
  carrying the old literal. Those will now be silently dropped (acknowledged without processing)
  rather than failing loudly — a correctness and observability regression.
- Recommendation for hand-off (not actioned here, no `src/main/java` file was modified): either
  accept the renamed literal as an intentional, documented breaking change to the message schema
  and formally re-freeze the spec to match, or have the migration developer restore
  backward-compatible routing (e.g., matching on a set of accepted storage-type literals, or
  translating legacy `"s3"` to `"azure-blob"` at ingestion).

### Finding 5 — SPEC DEFECT (pre-existing, not migration-caused): TC-WKR-001 expected thumbnail dimensions contradict unchanged no-upscale business logic
- TC-WKR-001 fails independently of Finding 4 (`storageType: "local"` matches, so
  `BlobFileProcessingService` genuinely processes the message).
- Spec expects a 600×400 thumbnail from a 300×200 source (i.e. upscaling), but
  `generateThumbnail`/`progressiveScaling` contains a "do not scale up images already smaller than
  the target box" guard that keeps the output at the original 300×200.
- Confirmed via git history that this exact no-upscale guard is byte-for-byte identical in the
  pre-migration baseline — this business logic was never touched by the migration (tasks 002–007).
  TC-WKR-003 (the `tiny.jpg` 1×1 boundary case) independently and correctly documents this same
  no-upscale rule.
- Classification: a Phase 1 baseline-authoring defect (the TC-WKR-001 expected dimensions were
  never verified against a live baseline run), not a migration regression. Requires a baseline
  re-freeze of `worker/src/test/test-cases/test-cases.md` (TC-WKR-001's `Resource Verification` to
  300×200) rather than being acted on unilaterally here. `test-cases.md` was **not** modified.

## Methodological note: message-queue-listener trigger mechanism under all-`mock` decision mode

Both modules' only event-sourced-subscriber entry points (`AbstractFileProcessingService
.processImage` in `worker`; `BackupMessageProcessor.processBackupMessage` in `web`, TC-WEB-018) are
`@ServiceBusListener`-annotated. The skill's default rule requires triggering such entry points by
producing a real event on the declared source via its SDK/wire protocol. However, both modules'
`infra-decision-table.md` set the message broker to `mock` (no testcontainer/emulator, no real
namespace — consistent with this task's explicit "mock all external services, no live endpoints"
instruction), and no Service Bus emulator is wired into this repository/environment. There is
therefore no mechanism available here to place a real message on a real or emulated queue.

The adopted adaptation — explicitly documented in both the planning table and this summary, not
concealed — was to autowire the real, fully-wired Spring-managed listener bean (never a
reimplementation, never a lower-level private helper) from the test's `ApplicationContext` and
invoke its public annotated method directly, with only the Azure SDK boundary
(`BlobContainerClient`/`BlobClient`/`ServiceBusReceivedMessageContext`) and the repository boundary
mocked. This exercises the actual production business logic end-to-end (thumbnail generation,
validation, ack/dead-letter decision) and is consistent with the existing pre-migration test
conventions already established in this codebase. It is flagged here as a known deviation from the
strict "wire-protocol" trigger rule, forced by the combination of (a) the explicit mock-everything
instruction for this task and (b) no Service Bus emulator being available in this environment — not
a shortcut chosen in place of an available real/testcontainer option.

## Other Issues Found (build/test-infrastructure only — not application bugs)

- `web/pom.xml`: Spring Boot 4 / Spring Framework 7 relocated `@AutoConfigureMockMvc` and
  `TestRestTemplate` support into new starter modules (`spring-boot-webmvc-test`,
  `spring-boot-resttestclient`, `spring-boot-restclient`) not transitively pulled by
  `spring-boot-starter-test` in this project; added as test-scope dependencies to let the generated
  tests compile. No production dependency was touched.
- `web/src/test/resources/application.properties` fully shadows (does not merge with)
  `web/src/main/resources/application.properties` on the test classpath; the multipart size-limit
  properties had to be restated in the test resource file for TC-WEB-004 to reach the real
  multipart-size-limit check.
- Both `web/pom.xml` and `worker/pom.xml` gained a `maven-failsafe-plugin` execution binding
  (`integration-test`/`verify` goals, `*PostMigrationIT` naming) so these tests run in the
  integration-test phase, separate from the pre-existing `mvn test` unit-test phase. No other build
  file or production source was modified.
- This environment's default `JAVA_HOME` is JDK 8; building/running this JDK-25-targeted project
  requires explicitly pointing `JAVA_HOME` at the installed `jdk-25.0.5.10002-hotspot` (see Runtime
  Execution Evidence above) — noted here for operators of any downstream (security/containerization)
  task that also needs to build this project.

## Frozen Spec / Scope Compliance

- `web/src/test/test-cases/**` and `worker/src/test/test-cases/**` (both `test-cases.md`,
  `infra-decision-table.md`, `testdata/`) were read but **not** modified.
- No `src/main/java` file in either module was modified in response to any finding — all five
  findings above are reported for hand-off, never patched around, and no test assertion was
  loosened to force a pass.
- No Azure credentials, live endpoints, or provisioned Azure resources were used anywhere in this
  verification (all dependencies mocked, per the decision tables and this task's explicit
  instruction).

## Test Artifacts

- Planning table (both modules, merged) + pre-generation trigger audit (web):
  `.github/modernize/modernization-plan/008-integrationTest-mocked-azure-services/post-migration-plan.md`
- Per-module detailed findings (authored by the generating agents, preserved for audit trail):
  `verification-summary-web.md`, `verification-summary-worker.md` (same folder)
- Generated tests (26 methods total, 1:1 with TC-WEB-001..018 + TC-WKR-001..008; no extra/infra-sanity
  test methods added):
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerDevProfilePostMigrationIT.java` (11 methods)
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerDevProfileRealServerPostMigrationIT.java` (2 methods)
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerNonDevProfilePostMigrationIT.java` (4 methods)
  - `web/src/test/java/com/microsoft/migration/assets/BackupListenerPostMigrationIT.java` (1 method)
  - `web/src/test/java/com/microsoft/migration/assets/PostMigrationTestFixtures.java` (shared fixture helper, no test methods)
  - `worker/src/test/java/com/microsoft/migration/assets/worker/service/WorkerMessageProcessingPostMigrationIT.java` (8 methods)
- Build changes: `web/pom.xml`, `worker/pom.xml` (failsafe plugin bindings + web's additional test-scope
  Spring Boot test-support dependencies); `web/src/test/resources/application.properties` (restated
  multipart limits + placeholder non-credential Azure endpoint/namespace properties needed for the
  mocked-bean Spring context to start).

## Pre-Run Validation Checklist (Step 6, re-certified independently)

- [x] 26 test methods == 26 `TC-*` total (18 TC-WEB-* + 8 TC-WKR-*); no extras, no missing; no
      infra-sanity/connectivity-only test class exists in either module.
- [x] Every TC referenced by exactly one method whose name embeds the TC ID (verified by inspecting
      the generated `*PostMigrationIT.java` files).
- [x] HTTP entry points triggered via `MockMvc`/`TestRestTemplate` against the real declared
      path/method; message-listener entry points triggered via the real Spring-managed bean's
      public annotated method (documented, necessary adaptation under all-`mock` decision mode, no
      broker/emulator available — see Methodological Note above).
- [x] Every `Expected Response`/`Resource Verification`/`Negative Verification` bullet is asserted;
      the 5 failing TCs fail exactly because their frozen-spec literal expected values differ from
      actual observed behavior — by design, not by omission.
- [x] Every `Data References` path loaded from the real fixture files under each module's
      `test-cases/testdata/`.
- [x] Each test method independent; fresh mock state per test; no `@Order`/shared mutable state.
- [x] All dependencies mocked at the SDK/repository boundary per the all-`mock` decision tables; no
      real or testcontainer-backed dependency was used anywhere; no Azure credentials present.
- [x] Independently re-run by the orchestrating session (not just trusted from agent reports): both
      module counts (18/3 web, 8/5 worker) reproduced exactly.

## Status Mapping and Downstream Impact

Per the skill's Step 6 outcome table: `*PostMigrationIT` executed for real in both modules (26 of 26
planned methods ran, 1:1 with the TC count), and all 8 failures are confirmed genuine
production-bug/platform-behavior/spec-defect findings (Findings 1–5) — none are test bugs, and no
assertion was loosened or workaround applied to force a pass. This run cannot be marked `success`.

Hand-off required (not completed within this verification task — no migration-developer or
infra-expert peer agent was available/addressable in this session to receive the hand-off
messages below; recorded here for the coordinating session/user to route):

| Finding | Recipient | Action needed |
|---|---|---|
| 1, 2 (message-text regressions) | Migration developer | Restore original `IOException` message text in `BlobFileStorageService`/`AzureBlobService`/`BlobKeyValidator`, or formally re-freeze the spec to accept the new wording |
| 3 (413 vs 500) | Migration developer / spec owner | Decide whether to add explicit `MaxUploadSizeExceededException` handling to restore 500, or accept 413 as the new contract and re-freeze |
| 4 (storageType literal) | Migration developer | Decide on backward-compatible storage-type routing, or re-freeze the spec to the new `"azure-blob"` literal |
| 5 (TC-WKR-001 dimensions) | Baseline re-freeze (Phase 1) | Correct `test-cases.md`'s TC-WKR-001 expected dimensions to 300×200 |

**Per this task's explicit requirement ("Any failure blocks security and container-artifact
tasks"): the downstream security-review and container-artifact-generation tasks are BLOCKED until
Findings 1–5 are resolved (either by code fixes + re-run to green, or by a formal baseline
re-freeze for Finding 5) and this verification is re-run to a 100%-pass result.**

**Final status: `failed`** — 18/26 `TC-*` pass; 8/26 fail for confirmed, non-test-bug reasons; no
further automated hand-off/resolution occurred within this task's execution.
