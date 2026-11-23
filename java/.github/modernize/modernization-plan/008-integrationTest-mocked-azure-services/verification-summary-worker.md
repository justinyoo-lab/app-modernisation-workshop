# Worker Module — Post-Migration Verification Summary

> Phase 3 ("Verify the Migration"), `verify-test-baseline` skill, `worker` module only.
> Planning table / trigger audit: `post-migration-plan-worker.md` (same folder).

## Runtime Execution Evidence

**Command (run from repo root `java/`):**

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-25.0.5.10002-hotspot"
.\mvnw.cmd -pl worker -am verify '-Dit.test=*PostMigrationIT' '-DfailIfNoTests=false'
```

(Maven Wrapper `mvnw.cmd` was used because no standalone Maven install exists in this environment;
`-am` builds the parent reactor module first.)

**Result (`WorkerMessageProcessingPostMigrationIT`, Failsafe):**

```
Tests run: 8, Failures: 5, Errors: 0, Skipped: 0
```

8 of 8 planned `TC-WKR-*` test methods executed == 8 `TC-*` planned in Step 4 (1:1, confirmed).
Build outcome: `BUILD FAILURE` (Failsafe `verify` goal fails the build on any `*PostMigrationIT`
failure) — this is expected, not a tooling problem; see Findings below for why each failure is a
legitimate test result, not an execution defect.

All other existing worker unit tests (`mvn test` phase, run as part of the same `verify`
invocation) continued to pass: `Tests run: 51, Failures: 0, Errors: 0, Skipped: 0` across
`BlobStorageConfigurationTest`, `DataSourceConfigurationTest`, `ServiceBusConfigurationTest`,
`ImageMetadataRepositoryTest`, `AbstractFileProcessingServiceTest`,
`AzureBlobFileProcessingServiceTest`, `BlobFileProcessingServiceTest`, `BlobKeyValidatorTest`.
These are unchanged, pre-existing tests, not part of this skill's output.

| TC ID | Method | Result | Mock-mechanism used |
|---|---|---|---|
| TC-WKR-001 | `tcWkr001_processImageLocalHappyPath` | **FAIL** (spec defect, see below) | Direct construction of real `BlobFileProcessingService`; `BlobContainerClient`/`BlobClient` Mockito mocks backed by `doAnswer` writing/reading real temp files |
| TC-WKR-002 | `tcWkr002_processImageObjectStorageHappyPath` | **FAIL** (production bug, see below) | Direct construction of real `AzureBlobFileProcessingService`; `BlobContainerClient`/`BlobClient`/`ImageMetadataRepository` Mockito mocks, repo seeded from `image-metadata-seed.json` |
| TC-WKR-003 | `tcWkr003_processImageLocalTinyNotUpscaled` | PASS | Same mechanism as TC-WKR-001 |
| TC-WKR-004 | `tcWkr004_processImageObjectStoragePortraitAlphaPreserved` | **FAIL** (production bug) | Same mechanism as TC-WKR-002 |
| TC-WKR-005 | `tcWkr005_processImageLocalSkipsOtherStorageType` | PASS | Same mechanism as TC-WKR-001 (no blob access expected/occurred) |
| TC-WKR-006 | `tcWkr006_processImageObjectStorageUnicodeKey` | **FAIL** (production bug) | Same mechanism as TC-WKR-002, single ad-hoc seeded row (Unicode `s3Key`) |
| TC-WKR-007 | `tcWkr007_processImageLocalSourceMissingDeadLetters` | PASS | Same mechanism as TC-WKR-001 (blob stubbed `exists()=false`) |
| TC-WKR-008 | `tcWkr008_processImageObjectStorageCorruptSourceDeadLetters` | **FAIL** (production bug) | Same mechanism as TC-WKR-002, real `corrupt.jpg` fixture bytes fed to `ImageIO` |

For every TC: all four dependency rows (local/blob storage, message broker, PostgreSQL) are
`mock` per `infra-decision-table.md`; no real or testcontainer-backed Azure resource or broker was
contacted, and no Azure credentials were used anywhere (`BlobContainerClient`, `BlobClient`, and
`ImageMetadataRepository` are all Mockito mocks; `ServiceBusReceivedMessageContext` is a Mockito
mock standing in for the broker's ack/nack channel — see the Trigger Mechanism section in the
planning table for why this is the correct adaptation for an all-`mock` decision table with no
broker/emulator available).

## Finding 1 — Confirmed PRODUCTION BUG: `storageType` literal regressed from `s3` to `azure-blob`

**TC-WKR-002, TC-WKR-004, TC-WKR-006, TC-WKR-008 all fail for the same root cause.** Verified with
real test execution (not just static review):

- The frozen spec's trigger body for these four cases carries the literal `"storageType": "s3"`
  (confirmed, byte-for-byte, unmodified in the generated tests — this is the pre-migration AWS S3
  holdover and was **not** "corrected" to make the tests pass).
- `AzureBlobFileProcessingService.getStorageType()` (current migrated code) returns
  `"azure-blob"`, not `"s3"`. Confirmed by reading `AzureBlobFileProcessingService.java`.
- Confirmed via `git show 62d8ff6:java/worker/.../S3FileProcessingService.java` that the
  **pre-migration** baseline's `getStorageType()` returned `"s3"` — i.e. the storage-type literal
  genuinely changed as part of this migration; this is not a pre-existing condition.
- `AbstractFileProcessingService.processImage` only performs download/thumbnail/upload work when
  `message.getStorageType().equals(getStorageType())`; since `"s3" != "azure-blob"`, all four tests
  hit the storage-type-mismatch branch, which is treated as success (`processingSuccess = true`,
  `context.complete()` called) with no file/DB work performed at all.
- Real execution evidence: all four tests fail at the first `Resource Verification` assertion
  (`assertNotNull(uploadedThumbnail.get(), ...)` or, for TC-WKR-008, the missing `deadLetter()`
  call), each annotated in the test source and failure output with
  `KNOWN PRODUCTION BUG (storageType literal mismatch, see class javadoc)`.

**This breaks the frozen message contract between the publisher of `image-processing` messages**
(the companion `web` module, or any other producer) **and the non-dev/object-storage worker
listener**: any message correctly carrying the pre-migration `storageType: "s3"` convention (or
any message a producer has not yet updated to `"azure-blob"`) will now be silently skipped by the
worker instead of processed, with no error surfaced (the message is acknowledged as if successful).
**Recommendation (hand-off to migration developer, not actioned here):** either align the message
producer(s) to send `"azure-blob"`, or make `AzureBlobFileProcessingService.getStorageType()`
return `"s3"` for backward routing compatibility (mirroring how `BlobFileProcessingService` kept
`getStorageType() == "local"` for routing compatibility, per its own class javadoc) — a decision
for the migration developer, not this verification task; no `src/main` file was modified.

## Finding 2 — SPEC DEFECT (not a migration bug): TC-WKR-001 expected dimensions contradict unchanged business logic

TC-WKR-001 fails independently of Finding 1 (its `storageType` is `"local"`, so no mismatch
occurs — `BlobFileProcessingService` actually processes the message).

- Spec text: *"A file `sample_thumbnail.jpg` exists ... with `max(width, height) = 600` and
  `min(width, height) = 400`"* for the 300x200 `sample.jpg` fixture (confirmed 300x200 via direct
  pixel inspection of the real fixture file).
- Actual behavior (verified by real execution): the thumbnail is produced at the **unchanged**
  300x200 — `generateThumbnail`/`progressiveScaling` contains a "don't scale up images already
  smaller than the target box" guard, and 300x200 is smaller than the computed 600x400 target box,
  so no upscaling occurs.
- Confirmed via `git show 62d8ff6:java/worker/.../AbstractFileProcessingService.java` that this
  exact no-upscale guard is **byte-for-byte identical in the pre-migration baseline** — this
  business logic was not touched by the migration. TC-WKR-003 (the `tiny.jpg` boundary case)
  independently documents and correctly asserts this same no-upscale rule for a 1x1 source.
- **Classification: spec/baseline-authoring defect from Phase 1** (the expected dimensions for
  TC-WKR-001 were never actually verified against a live baseline run), not a migration-introduced
  regression. Per the `verify-test-baseline` skill (Step 7/Step 8), the generated test is **not**
  patched to assert `300x200` instead — the frozen spec's literal numbers are kept as written so
  the conflict is surfaced rather than hidden, and the finding is reported here for a baseline
  re-freeze (amending `test-cases.md`'s TC-WKR-001 `Resource Verification` to `300x200`) rather than
  acted on unilaterally. `test-cases.md` was **not** modified by this task.

## Test Artifacts

- Planning table + pre-generation trigger audit:
  `.github/modernize/modernization-plan/008-integrationTest-mocked-azure-services/post-migration-plan-worker.md`
- Generated tests: `worker/src/test/java/com/microsoft/migration/assets/worker/service/WorkerMessageProcessingPostMigrationIT.java`
  (8 methods, 1:1 with TC-WKR-001..008; no extra/infra-sanity test methods added)
- Build change: `worker/pom.xml` — added a `maven-failsafe-plugin` execution binding
  `integration-test`/`verify` goals so `*IT`/`*PostMigrationIT` tests run in the integration-test
  phase, separate from `mvn test`. (`web/pom.xml` was not touched.)

## Pre-Run Validation Checklist (Step 6, self-certified before execution)

- [x] 8 test methods == 8 `TC-WKR-*` (no extras, no missing).
- [x] Every TC referenced by exactly one method whose name embeds the TC ID.
- [x] No infra-sanity/connectivity-only test class exists.
- [x] Trigger line in every test invokes the real, Spring-bean-shaped production class's public
      `processImage(...)` method — never a reimplementation, never a lower-level helper call as the
      trigger.
- [x] Every `Expected Response` / `Resource Verification` / `Negative Verification` bullet has a
      corresponding assertion (ack/nack, dimensions, content-type, DB row state via captured
      `save()` argument, "no additional row created", "other rows unchanged", "no file/object
      created").
- [x] Every `Data References` path is loaded from the real fixture file
      (`testdata/inputs/*`, `testdata/seed-data/image-metadata-seed.json`) via `Files.readAllBytes`
      / Jackson, never a hand-typed substitute.
- [x] Each test method is independent (fresh mocks per method, `@TempDir`/temp blob maps per
      method, no shared/ordered state).
- [x] All dependencies mocked at the SDK/repository boundary, matching the all-`mock` decision
      table; no real/testcontainer dependency exists for this module, so no full-stack boot was
      required.

## Status Mapping

Per the skill's Step 6 outcome table, since `*PostMigrationIT` executed for real (8 of 8 planned
methods ran) and genuine failures occurred whose causes are a confirmed production bug (Finding 1)
and a spec defect requiring re-freeze (Finding 2) — not test bugs, and no workaround was applied —
this run cannot be marked `success`. Hand-off is required: Finding 1 to the migration developer,
Finding 2 to a baseline re-freeze of `test-cases.md`. No further action was taken on
`src/main/java` or on the frozen `test-cases/` folder from this task.
