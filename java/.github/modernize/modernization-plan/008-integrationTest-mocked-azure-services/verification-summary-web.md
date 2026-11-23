# Web Module — Post-Migration Verification Summary

> Phase 3 ("Verify the Migration"), `verify-test-baseline` skill, `web` module only.
> Planning table / trigger audit: `post-migration-plan-web.md`, `pre-generation-trigger-audit-web.md` (same folder).

## Runtime Execution Evidence

**Command (run from repo root `java/`):**

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-25.0.5.10002-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
.\mvnw.cmd -pl web -am verify "-Dit.test=*PostMigrationIT" "-Dsurefire.skip=true"
```

(Maven Wrapper `mvnw.cmd` was used because no standalone Maven install exists on PATH in this
environment; `-am` builds the parent reactor module first; `-Dsurefire.skip=true` — not
`-DskipTests=true`, which would also skip Failsafe — runs only the Failsafe integration-test phase
against the generated `*PostMigrationIT` classes.)

**Final result (Failsafe, all four `*PostMigrationIT` classes):**

```
Tests run: 18, Failures: 3, Errors: 0, Skipped: 0
```

18 of 18 planned `TC-WEB-*` test methods executed == 18 `TC-WEB-*` planned in Step 4 (1:1,
confirmed, no extras/missing). Build outcome: `BUILD FAILURE` (Failsafe `verify` goal fails the
build on any `*PostMigrationIT` failure) — expected, not a tooling problem; all 3 failures are
genuine production/platform-behavior discrepancies (see Findings below), not test bugs, and no
assertion was loosened to make them pass.

All pre-existing `web` unit tests (`mvn test` phase, run as part of the same `verify` invocation)
continued to pass unchanged: `Tests run: 62, Failures: 0, Errors: 0, Skipped: 0` across
`BlobStorageConfigurationTest`, `DataSourceConfigurationTest`, `ServiceBusConfigurationTest`,
`ImageMetadataRepositoryTest`, `AzureBlobServiceTest`, `BackupMessageProcessorTest`,
`BlobFileStorageServiceTest`, `BlobKeyValidatorTest`. These are unchanged, pre-existing tests, not
part of this skill's output.

## Per-TC Breakdown

| TC ID | Test class → method | Result | Mock-mechanism used |
|---|---|---|---|
| TC-WEB-001 | `StorageControllerDevProfilePostMigrationIT.tcWeb001_uploadDevHappyPath` | PASS | MockMvc multipart upload; `BlobContainerClient`/`BlobClient` Mockito mocks capturing uploaded bytes and headers; `ServiceBusTemplate.send` captured via `ArgumentCaptor`; `ImageMetadataRepository.save` captured |
| TC-WEB-002 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb002_uploadNonDevHappyPath` | PASS | Same mechanism, non-dev profile (`AzureBlobService`) |
| TC-WEB-003 | `StorageControllerDevProfilePostMigrationIT.tcWeb003_uploadEmptyFileRejected` | PASS | MockMvc multipart with an empty byte array; verifies no blob/queue/DB interaction occurred |
| TC-WEB-004 | `StorageControllerDevProfileRealServerPostMigrationIT.tcWeb004_uploadExceedsMaxSize` | **FAIL** (platform-behavior discrepancy, Finding 3) | Real over-the-wire HTTP via `TestRestTemplate` + `webEnvironment=RANDOM_PORT` against the real 10MB fixture |
| TC-WEB-005 | `StorageControllerDevProfilePostMigrationIT.tcWeb005_uploadPathTraversalFilenameRejected` | **FAIL** (production bug, Finding 1) | MockMvc multipart with filename `../tiny.jpg`; asserts the exact frozen-spec flash message |
| TC-WEB-006 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb006_uploadUnicodeFilenameAccepted` | PASS | MockMvc multipart, Unicode filename, byte-identical content + DB row assertions |
| TC-WEB-007 | `StorageControllerDevProfileRealServerPostMigrationIT.tcWeb007_uploadQueueUnavailable` | PASS | Real over-the-wire HTTP via `TestRestTemplate`; `ServiceBusTemplate.send` stubbed to throw, asserting real HTTP 500 |
| TC-WEB-008 | `StorageControllerDevProfilePostMigrationIT.tcWeb008_listDevHappyPath` | PASS | `blobContainerClient.listBlobs()` stubbed via a real `PagedIterable` wrapping a mocked `PagedResponse`, with real `BlobItem`/`BlobItemProperties` instances |
| TC-WEB-009 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb009_listNonDevHappyPath` | PASS | Same `PagedIterable`/`BlobItem` mechanism + `ImageMetadataRepository.findAll()` stubbed from seed JSON |
| TC-WEB-010 | `StorageControllerDevProfilePostMigrationIT.tcWeb010_listEmptyStorage` | PASS | Same mechanism, empty `PagedIterable` |
| TC-WEB-011 | `StorageControllerDevProfilePostMigrationIT.tcWeb011_viewPageHappyPath` | PASS | Same mechanism, single `BlobItem` |
| TC-WEB-012 | `StorageControllerDevProfilePostMigrationIT.tcWeb012_viewBinaryHappyPath` | PASS | `BlobClient.downloadContent()` stubbed to return real fixture bytes via `BinaryData` |
| TC-WEB-013 | `StorageControllerDevProfilePostMigrationIT.tcWeb013_viewPageNotFound` | PASS | Empty `PagedIterable`; asserts "Image not found" flash + no blob access |
| TC-WEB-014 | `StorageControllerDevProfilePostMigrationIT.tcWeb014_viewBinaryNotFound` | PASS | `BlobClient.exists()` stubbed `false` |
| TC-WEB-015 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb015_deleteNonDevHappyPath` | PASS | `ImageMetadataRepository.findAll()` seeded from JSON; original + thumbnail `BlobClient`s mocked; `delete()` argument captured |
| TC-WEB-016 | `StorageControllerDevProfilePostMigrationIT.tcWeb016_deleteDevHappyPath` | PASS | `BlobClient.exists()` stubbed `true` for original + thumbnail; `deleteIfExists()` verified |
| TC-WEB-017 | `StorageControllerDevProfilePostMigrationIT.tcWeb017_deleteNotFound` | **FAIL** (production bug, Finding 2) | `BlobClient.exists()` stubbed `false`; asserts the exact frozen-spec flash message |
| TC-WEB-018 | `BackupListenerPostMigrationIT.tcWeb018_backupListenerAcknowledgesMessage` | PASS | Real `BackupMessageProcessor` Spring bean autowired from a `backup`-profile context, invoked directly with a deserialized spec-literal `ImageProcessingMessage`; `ServiceBusReceivedMessageContext` Mockito mock, `.complete()` verified (forced adaptation, see planning doc) |

For every TC: all dependency rows (local/blob storage, message broker, PostgreSQL) are `mock` per
`infra-decision-table.md`; `BlobContainerClient`, `ServiceBusTemplate`, and
`ImageMetadataRepository` are Mockito `@MockitoBean`s for the full duration of every test — no
real or testcontainer-backed Azure Blob Storage, Service Bus, or PostgreSQL resource was ever
contacted, and no Azure credentials exist anywhere in the test sources.

## Finding 1 — Confirmed PRODUCTION BUG: upload path-traversal rejection message text changed (TC-WEB-005)

Verified with real test execution, not just static review. Uploading a file named `../tiny.jpg`
under the `dev` profile:

- **Expected** (frozen spec, `test-cases.md`): flash attribute `error` =
  `Failed to upload file: Cannot store file with relative path outside current directory`
- **Actual** (observed from the real run):
  `Failed to upload file: Cannot access blob with relative path outside the container: ../tiny.jpg`

Root cause: `S3Controller.uploadObject` → `BlobFileStorageService.uploadObject` (`dev` profile) now
routes the filename through `BlobKeyValidator.sanitize(...)`, which throws
`IOException("Cannot access blob with relative path outside the container: " + rawKey)` instead of
the original `"Cannot store file with relative path outside current directory"` message. The
behavior (upload rejected) is correct; only the externally-visible error message contract changed.
This is a genuine migration regression in a user-facing message, not a test bug — the test
assertion was **not** loosened to match the new text.

## Finding 2 — Confirmed PRODUCTION BUG: delete-not-found rejection message text changed (TC-WEB-017)

Deleting a non-existent key (`does-not-exist.jpg`) under the `dev` profile:

- **Expected** (frozen spec): flash attribute `error` starts with
  `Failed to delete file: File not found: ` and ends with `does-not-exist.jpg`
- **Actual** (observed): `Failed to delete file: Blob not found: does-not-exist.jpg`

Same class of regression as Finding 1 — "File not found" was replaced with "Blob not found" in the
migrated `BlobFileStorageService`/`AzureBlobService` error path. Behavior is correct (the request is
still rejected with the key in the message); only the message text contract changed.

## Finding 3 — Confirmed PLATFORM-BEHAVIOR DISCREPANCY: oversized upload now returns 413, not 500 (TC-WEB-004)

Uploading a file exceeding `spring.servlet.multipart.max-file-size=10MB`:

- **Expected** (frozen spec): `500 Internal Server Error`
- **Actual** (observed via real over-the-wire HTTP through `TestRestTemplate` against a genuinely
  running embedded Tomcat, `webEnvironment=RANDOM_PORT`): `413 Payload Too Large`
  (`HttpStatus.PAYLOAD_TOO_LARGE` / `CONTENT_TOO_LARGE`)

Root cause: Spring Framework 6.1+ (bundled with the Spring Boot 4 target of this migration) added
built-in `DefaultHandlerExceptionResolver` handling that maps `MaxUploadSizeExceededException` to
413 instead of letting it propagate uncaught to a 500, as it did on the pre-migration Spring
Framework version the frozen spec was authored against. This is a genuine framework-version-driven
behavior change, not application code and not fixable by editing `src/main/java` — but per the
skill's rules the test assertion was **not** loosened to match the new status code; TC-WEB-004
fails exactly as the frozen spec requires.

**Trigger-mechanism correction required for this finding to be observable at all:** the original
architecture note assumed MockMvc over a fully booted `@SpringBootTest` context would suffice for
TC-WEB-004/TC-WEB-007. Empirically this is false — MockMvc's `multipart()` builder bypasses real
servlet-container multipart parsing and has no container-level error-page dispatch, so neither
`MaxUploadSizeExceededException` nor an uncaught `RuntimeException` can ever surface as a real HTTP
status this way. Both cases were moved to a dedicated `StorageControllerDevProfileRealServerPostMigrationIT`
class using `webEnvironment=RANDOM_PORT` + `TestRestTemplate` to drive real over-the-wire HTTP — see
the planning doc for full justification. This correction is a test-generation fix, not a loosening
of any assertion; both TC-WEB-004's expected-500 assertion and TC-WEB-007's expected-500 assertion
were kept exactly as specified (TC-WEB-007 passes with this trigger; TC-WEB-004 still fails,
correctly surfacing Finding 3).

## Other Issues Found (incidental, build/test-infrastructure — not application bugs)

- **Spring Boot 4 / Spring Framework 7 test-module relocations**: `@AutoConfigureMockMvc` moved
  from `spring-boot-test-autoconfigure` into a new `spring-boot-webmvc-test` module; `TestRestTemplate`
  / `@AutoConfigureTestRestTemplate` moved into a new `spring-boot-resttestclient` module (which
  transitively needs `spring-boot-restclient` for `RestTemplateBuilder`, not auto-pulled). None of
  these are declared as transitive dependencies of `spring-boot-starter-test` in this project;
  added explicitly as test-scope dependencies in `web/pom.xml` purely to get the generated tests to
  compile/run — no production dependency was touched.
- **Test-classpath resource shadowing**: `web/src/test/resources/application.properties` fully
  shadows (does not merge with) `web/src/main/resources/application.properties` on the Maven test
  classpath (same relative path; `target/test-classes` precedes `target/classes`). The
  `spring.servlet.multipart.max-file-size`/`max-request-size` properties needed to be restated in
  the test resource file for TC-WEB-004 to ever reach the real multipart-size-limit check.
- **Mockito "unfinished stubbing" self-inflicted test bug (fixed)**: an earlier draft of the
  `pagedIterableOf(...)` / `blobItem(...)` test helpers nested a `when(...)` call as the direct
  argument of another, not-yet-completed `when(x).thenReturn(...)` call (i.e.
  `when(blobContainerClient.listBlobs()).thenReturn(pagedIterableOf(...))` where `pagedIterableOf`
  itself called `when(...).thenReturn(...)` internally) — a classic Mockito anti-pattern that
  corrupts the global "ongoing stubbing" state and manifests as `UnfinishedStubbingException` on
  the *next* mock interaction. Fixed by always assigning the inner stub's result to a local variable
  before passing it to the outer `when(...).thenReturn(...)`. Separately, `BlobItem`/`BlobItemProperties`
  (both `final` Azure SDK classes with public no-arg constructors and fluent setters) are now
  constructed as real instances instead of being Mockito-mocked, and `PagedIterable<BlobItem>` is
  built from its own public `Supplier<PagedResponse<T>>` constructor wrapping a mocked `PagedResponse`
  (a plain interface) rather than mocking `PagedIterable` itself — both changes are good practice
  independent of the stubbing-order bug and make the test helpers slightly more robust.
- **Test counting-logic test bug (fixed)**: an early version of the list-page assertions counted
  every raw `data-key="` substring occurrence in the full HTML response body. `list.html` also
  embeds the literal text `data-key="` inside an unrelated client-side JS template literal (the
  auto-refresh polling script's `getThumbnailKey` lookup), inflating the count by exactly one
  regardless of the actual number of rendered items. Fixed by anchoring the count to the rendered
  item wrapper (`class="col-md-4 mb-4" ... data-key="..."`).
- Removed an initial `-javaagent:${org.mockito:mockito-core:jar}` Failsafe `argLine` (plus its
  supporting `maven-dependency-plugin` resolution execution) from `web/pom.xml` that had been added
  while chasing the UnfinishedStubbingException above. It was confirmed **not** to be the actual
  fix (the self-attach warning disappeared but the error persisted) and was removed once the real
  root cause (the nested-`when()` anti-pattern) was found, to avoid leaving a non-functional
  workaround in the build for future maintainers.

## Frozen Spec / Scope Compliance

- `web/src/test/test-cases/test-cases.md` and `infra-decision-table.md` were read but **not**
  modified.
- No file under `worker/**` was read for editing purposes or modified.
- `BlobKeyValidator` (package-private) was never called directly; it is only exercised indirectly
  through `S3Controller`/`BlobFileStorageService`/`AzureBlobService`.
- No `src/main/java` file was modified in response to any of the three findings above; all three
  are reported as discrepancies for hand-off, not patched around.

## Test Artifacts

- Planning table + architecture-correction notes:
  `.github/modernize/modernization-plan/008-integrationTest-mocked-azure-services/post-migration-plan-web.md`
- Pre-generation trigger audit:
  `.github/modernize/modernization-plan/008-integrationTest-mocked-azure-services/pre-generation-trigger-audit-web.md`
- Generated tests (18 methods total, 1:1 with TC-WEB-001..018; no extra/infra-sanity test methods
  added):
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerDevProfilePostMigrationIT.java` (11 methods)
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerDevProfileRealServerPostMigrationIT.java` (2 methods)
  - `web/src/test/java/com/microsoft/migration/assets/StorageControllerNonDevProfilePostMigrationIT.java` (4 methods)
  - `web/src/test/java/com/microsoft/migration/assets/BackupListenerPostMigrationIT.java` (1 method)
  - `web/src/test/java/com/microsoft/migration/assets/PostMigrationTestFixtures.java` (shared fixture/seed-JSON loading helper, no test methods)
- Build change: `web/pom.xml` — added a `maven-failsafe-plugin` execution binding
  `integration-test`/`verify` goals so `*IT`/`*PostMigrationIT` tests run in the integration-test
  phase, separate from `mvn test`; added `spring-boot-webmvc-test`, `spring-boot-resttestclient`,
  and `spring-boot-restclient` test-scope dependencies required for the generated tests to compile.
  (`worker/pom.xml` was not touched.)
- Config change: `web/src/test/resources/application.properties` — restated the multipart
  size-limit properties (needed because this file fully shadows the main-resources file on the
  test classpath) plus placeholder (non-credential) Azure Blob/Service Bus endpoint/namespace
  properties required for the Spring context to start with `BlobContainerClient`/`ServiceBusTemplate`
  beans mocked out.

## Pre-Run Validation Checklist (Step 6, self-certified before execution)

- [x] 18 test methods == 18 `TC-WEB-*` (no extras, no missing).
- [x] Every TC referenced by exactly one method whose name embeds the TC ID.
- [x] No infra-sanity/connectivity-only test class exists.
- [x] Every HTTP trigger invokes `MockMvc`/`TestRestTemplate` against the real, declared
      path/method — never a reimplementation, never a lower-level service call as the trigger
      (TC-WEB-018 is the sole, explicitly documented exception, forced by the all-`mock` decision
      table with no broker/emulator available).
- [x] Every `Expected Response` / `Resource Verification` / `Negative Verification` bullet has a
      corresponding assertion: HTTP status, flash attributes, captured Service Bus message
      fields, captured DB `save()`/`delete()` argument field values, byte-identical file
      comparisons against real fixture bytes, content-type headers, 404/500(/413) bodies.
  - **Exception, by design**: TC-WEB-004's and TC-WEB-005's and TC-WEB-017's status/message
    assertions are the frozen spec's literal expected values, which now fail against the actual
    migrated/platform behavior — this is the intended, documented outcome (Findings 1–3), not an
    omission.
- [x] Every `Data References` path is loaded from the real fixture file
      (`testdata/inputs/*`, `testdata/seed-data/image-metadata-seed.json`) via classpath
      resource loading, never a hand-typed substitute.
- [x] Each test method is independent (fresh `@MockitoBean` state per method via Spring's
      automatic mock reset, no shared mutable state, no `@Order`).
- [x] All dependencies mocked at the SDK/repository boundary, matching the all-`mock` decision
      table; `BlobContainerClient`, `ServiceBusTemplate`, and `ImageMetadataRepository` are
      `@MockitoBean`s in every test class; no real/testcontainer dependency was used anywhere.

## Status Mapping

Per the skill's Step 6 outcome table, since `*PostMigrationIT` executed for real (18 of 18 planned
methods ran) and the 3 failures are all confirmed production/platform-behavior discrepancies
(Findings 1–3) — not test bugs — and no assertion was loosened or workaround applied to force a
pass, this run cannot be marked `success`. Hand-off is required: Findings 1 and 2 to the migration
developer (restore the original error-message text or formally re-baseline the spec), Finding 3 to
either the migration developer or a spec re-freeze decision (accept the Spring Framework 6.1+
413-vs-500 behavior change, or add explicit exception handling in `src/main/java` to restore the
500). No `src/main/java` file and no file under `web/src/test/test-cases/` or `worker/**` was
modified by this task.
