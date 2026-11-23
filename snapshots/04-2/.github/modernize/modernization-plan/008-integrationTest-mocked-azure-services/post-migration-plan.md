# Post-Migration Test Plan — All In-Scope Modules (web, worker)

> Task: 008-integrationTest-mocked-azure-services. This single file is the Step 4 mandatory planning artifact covering all 26 TC-* (18 TC-WEB-*, 8 TC-WKR-*). Per-module detail preserved verbatim below.

---

# Post-Migration Test Plan — `web` module

Source spec: `web/src/test/test-cases/test-cases.md` (18 cases, TC-WEB-001..018)
Infra decision table: `web/src/test/test-cases/infra-decision-table.md` — every dependency (local/blob storage, Service Bus, PostgreSQL) is `mock`.

Test classes (JUnit 5, full `@SpringBootTest` application context; `BlobContainerClient` / `ServiceBusTemplate` / `ImageMetadataRepository` all `@MockitoBean`):

- `StorageControllerDevProfilePostMigrationIT` — `@ActiveProfiles("dev")`, `webEnvironment = MOCK` + `@AutoConfigureMockMvc` (routes to `BlobFileStorageService`) — all dev-profile cases except TC-WEB-004/007
- `StorageControllerDevProfileRealServerPostMigrationIT` — `@ActiveProfiles("dev")`, `webEnvironment = RANDOM_PORT` + `TestRestTemplate` (`@AutoConfigureTestRestTemplate`) — TC-WEB-004 and TC-WEB-007 only; see "Note on the dev-profile real-server split" below
- `StorageControllerNonDevProfilePostMigrationIT` — no active profile (default profile satisfies `!dev`, routes to `AzureBlobService`), `webEnvironment = MOCK` + `@AutoConfigureMockMvc`
- `BackupListenerPostMigrationIT` — `@ActiveProfiles("backup")`, `webEnvironment = NONE` (no HTTP entry point involved)

`PagedIterable<BlobItem>` results from `blobContainerClient.listBlobs()` are built from a real `PagedIterable` (its public `Supplier<PagedResponse<T>>` constructor) wrapping a Mockito-mocked `PagedResponse` (a plain interface), rather than mocking `PagedIterable`/`BlobItem` directly — `BlobItem`/`BlobItemProperties` are constructed as real instances via their public no-arg constructors and fluent setters (both are `final` Azure SDK classes but ship with those public constructors, so there's no need to mock them at all). This also sidesteps a Mockito `UnfinishedStubbingException` that was traced to nesting a `when(...)` call as the argument of `.thenReturn(...)` on another `when(...)` (see Known Issues in the final report) — stubs for `listBlobs()` are always assigned to a local variable first, then passed to `thenReturn`.

## TC → Test Planning Table

| TC ID | Test Location (class → method) | Declared Entry Point | Trigger Mechanism (concrete) | Fixtures Loaded (from Data References) | Non-mock Deps Touched | Config Source | Cleanup Path |
|---|---|---|---|---|---|---|---|
| TC-WEB-001 | `StorageControllerDevProfilePostMigrationIT.tcWeb001_uploadDevHappyPath` | `POST /storage/upload` | MockMvc `multipart("/storage/upload")` with part `file` = real bytes of `sample.jpg` | `testdata/inputs/sample.jpg` | none (all mock) | `web/src/test/resources/application.properties` (`dev` profile) | n/a — new `@MockitoBean` instances per test class instance; no shared state |
| TC-WEB-002 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb002_uploadNonDevHappyPath` | `POST /storage/upload` | MockMvc `multipart("/storage/upload")` with part `file` = real bytes of `sample.jpg` | `testdata/inputs/sample.jpg` | none (all mock) | `web/src/test/resources/application.properties` (no profile) | n/a |
| TC-WEB-003 | `StorageControllerDevProfilePostMigrationIT.tcWeb003_uploadEmptyFileRejected` | `POST /storage/upload` | MockMvc `multipart("/storage/upload")` with part `file` = empty byte array, filename `empty.jpg` | none (empty payload constructed inline per spec) | none | same as above | n/a |
| TC-WEB-004 | `StorageControllerDevProfileRealServerPostMigrationIT.tcWeb004_uploadExceedsMaxSize` | `POST /storage/upload` | **Real over-the-wire HTTP** via `TestRestTemplate` against `webEnvironment = RANDOM_PORT` (NOT MockMvc — see note below), posting real bytes of `oversized-10mb-plus.bin` (10,486,784 bytes) | `testdata/inputs/oversized-10mb-plus.bin` | none | `spring.servlet.multipart.max-file-size=10MB` from `web/src/main/resources/application.properties` (unchanged; also restated in `web/src/test/resources/application.properties`, which otherwise fully shadows it on the test classpath) | n/a |
| TC-WEB-005 | `StorageControllerDevProfilePostMigrationIT.tcWeb005_uploadPathTraversalFilenameRejected` | `POST /storage/upload` | MockMvc `multipart("/storage/upload")` with part `file` = real bytes of `tiny.jpg`, filename `../tiny.jpg` | `testdata/inputs/tiny.jpg` | none | same as above | n/a |
| TC-WEB-006 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb006_uploadUnicodeFilenameAccepted` | `POST /storage/upload` | MockMvc `multipart("/storage/upload")` with part `file` = real bytes of `sample-portrait.png`, filename `테스트 이미지.png` | `testdata/inputs/sample-portrait.png` | none | same as above | n/a |
| TC-WEB-007 | `StorageControllerDevProfileRealServerPostMigrationIT.tcWeb007_uploadQueueUnavailable` | `POST /storage/upload` | **Real over-the-wire HTTP** via `TestRestTemplate` against `webEnvironment = RANDOM_PORT`, posting real bytes of `tiny.jpg`; `serviceBusTemplate.send(...)` stubbed to throw to simulate broker unreachable | `testdata/inputs/tiny.jpg` | none | same as above | n/a |
| TC-WEB-008 | `StorageControllerDevProfilePostMigrationIT.tcWeb008_listDevHappyPath` | `GET /storage` | MockMvc `get("/storage")`; `blobContainerClient.listBlobs()` stubbed to return 3 `BlobItem`s built from the 3 input fixtures | `testdata/inputs/sample.jpg`, `testdata/inputs/sample-portrait.png`, `testdata/inputs/tiny.jpg` | none | same as above | n/a |
| TC-WEB-009 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb009_listNonDevHappyPath` | `GET /storage` | MockMvc `get("/storage")`; `blobContainerClient.listBlobs()` + `imageMetadataRepository.findAll()` stubbed from the seed JSON | `testdata/seed-data/image-metadata-seed.json`, `testdata/inputs/sample.jpg`, `testdata/inputs/sample-portrait.png`, `testdata/inputs/tiny.jpg` | none | same as above | n/a |
| TC-WEB-010 | `StorageControllerDevProfilePostMigrationIT.tcWeb010_listEmptyStorage` | `GET /storage` | MockMvc `get("/storage")`; `blobContainerClient.listBlobs()` stubbed to return an empty `PagedIterable` | none | none | same as above | n/a |
| TC-WEB-011 | `StorageControllerDevProfilePostMigrationIT.tcWeb011_viewPageHappyPath` | `GET /storage/view-page/{key}` | MockMvc `get("/storage/view-page/sample.jpg")`; `blobContainerClient.listBlobs()` stubbed with `sample.jpg` | `testdata/inputs/sample.jpg` | none | same as above | n/a |
| TC-WEB-012 | `StorageControllerDevProfilePostMigrationIT.tcWeb012_viewBinaryHappyPath` | `GET /storage/view/{key}` | MockMvc `get("/storage/view/sample.jpg")`; `blobContainerClient.getBlobClient("sample.jpg")` stubbed to an existing blob whose `downloadContent()` returns the real fixture bytes | `testdata/inputs/sample.jpg` | none | same as above | n/a |
| TC-WEB-013 | `StorageControllerDevProfilePostMigrationIT.tcWeb013_viewPageNotFound` | `GET /storage/view-page/{key}` | MockMvc `get("/storage/view-page/does-not-exist.jpg")`; `blobContainerClient.listBlobs()` stubbed empty | none | none | same as above | n/a |
| TC-WEB-014 | `StorageControllerDevProfilePostMigrationIT.tcWeb014_viewBinaryNotFound` | `GET /storage/view/{key}` | MockMvc `get("/storage/view/does-not-exist.jpg")`; `blobClient.exists()` stubbed `false` | none | none | same as above | n/a |
| TC-WEB-015 | `StorageControllerNonDevProfilePostMigrationIT.tcWeb015_deleteNonDevHappyPath` | `POST /storage/delete/{key}` | MockMvc `post("/storage/delete/{key}")`; `imageMetadataRepository.findAll()` stubbed from seed JSON, `blobContainerClient.getBlobClient(...)` stubbed existing for original + thumbnail | `testdata/seed-data/image-metadata-seed.json`, `testdata/inputs/sample.jpg` | none | same as above | n/a |
| TC-WEB-016 | `StorageControllerDevProfilePostMigrationIT.tcWeb016_deleteDevHappyPath` | `POST /storage/delete/{key}` | MockMvc `post("/storage/delete/sample.jpg")`; `blobClient.exists()` stubbed `true` for original + thumbnail | `testdata/inputs/sample.jpg` | none | same as above | n/a |
| TC-WEB-017 | `StorageControllerDevProfilePostMigrationIT.tcWeb017_deleteNotFound` | `POST /storage/delete/{key}` | MockMvc `post("/storage/delete/does-not-exist.jpg")`; `blobClient.exists()` stubbed `false` | none | none | same as above | n/a |
| TC-WEB-018 | `BackupListenerPostMigrationIT.tcWeb018_backupListenerAcknowledgesMessage` | Listener bound to queue `image-processing` (`BackupMessageProcessor.processBackupMessage`, profile `backup`) | **Forced adaptation** (see note below): real `BackupMessageProcessor` bean autowired from the `backup`-profile `ApplicationContext`; `processBackupMessage` invoked directly with an `ImageProcessingMessage` deserialized from the spec's exact JSON trigger body and a Mockito-mocked `ServiceBusReceivedMessageContext` | none (message body constructed inline from the spec's literal JSON, matching `Data References: none`) | none | `web/src/test/resources/application.properties` (`backup` profile), `webEnvironment = NONE` | n/a |

### Note on the dev-profile real-server split (TC-WEB-004 / TC-WEB-007)

The original architecture note assumed MockMvc over a fully booted `@SpringBootTest` context would suffice for TC-WEB-004 (`MaxUploadSizeExceededException` → 500). Empirically this is **not** the case: MockMvc's `multipart()` builder constructs an already-parsed `MockMultipartHttpServletRequest` directly, bypassing real servlet-container multipart parsing entirely, so `spring.servlet.multipart.max-file-size` is never enforced and `MaxUploadSizeExceededException` can never be triggered through it. The same applies to TC-WEB-007's requirement that an uncaught `RuntimeException` surface as a real HTTP 500: MockMvc's mock dispatch has no container-level error-page machinery, so uncaught exceptions propagate out of `mockMvc.perform(...)` as a wrapped `ServletException` instead of becoming a 500 response. Both behaviors require a genuinely running embedded server reached over real HTTP. These two cases were therefore moved into a dedicated `StorageControllerDevProfileRealServerPostMigrationIT` class using `webEnvironment = RANDOM_PORT` + `TestRestTemplate` (`@AutoConfigureTestRestTemplate`), kept separate from the other dev-profile MockMvc tests because combining `@AutoConfigureMockMvc` with a non-`MOCK` `webEnvironment` in the same class makes MockMvc itself issue real over-the-wire HTTP (per Spring Boot docs), which is unnecessary complexity for the 9 other dev-profile cases that don't need it.

### Note on TC-WEB-018's trigger (forced adaptation)

The declared entry point is a message-queue listener. Per the skill's normal rule, the trigger should publish a real message onto the `image-processing` queue via the Service Bus SDK/wire protocol. However, the infra-decision-table marks Service Bus as `mock` for this task (no testcontainer/emulator, no real namespace, no broker wired anywhere in this repo/environment), so there is no mechanism in this environment to put a real message on a real or emulated queue. Per the task's explicit instruction, the only faithful-to-production trigger available under this constraint is to autowire the real Spring-managed `BackupMessageProcessor` bean (not a reimplementation or a private helper) from a dedicated `backup`-profile `ApplicationContext` and invoke its public `processBackupMessage(ImageProcessingMessage, ServiceBusReceivedMessageContext)` directly, with the `ServiceBusReceivedMessageContext` mocked so `.complete()` can be verified. This is documented here as a necessary, pre-approved deviation from the strict "produce a real event on the source" rule — not a shortcut chosen to avoid a real dependency that was otherwise available.



---

# Worker Module — Post-Migration Test Plan

> Generated by the `verify-test-baseline` skill, Phase 3 ("Verify the Migration"), for the `worker`
> module only. Source spec: `worker/src/test/test-cases/test-cases.md` +
> `worker/src/test/test-cases/infra-decision-table.md` (both frozen, read-only).

## Mapping note (frozen spec → current migrated code)

The frozen `test-cases.md` was authored referencing the pre-migration bean names
(`LocalFileProcessingService`, `S3FileProcessingService`) and the `storageType` literal `"s3"` for
the non-dev profile, because it captures the baseline **behavior contract**, not current class
names. The current migrated code's entry point is the single `processImage` method declared in
`AbstractFileProcessingService` (annotated `@ServiceBusListener`), concretely implemented by:

- `BlobFileProcessingService` (`@Profile("dev")`, `getStorageType() == "local"`) — exercises
  TC-WKR-001/003/005/007 ("local-storage processor").
- `AzureBlobFileProcessingService` (`@Profile("!dev")`, `getStorageType() == "azure-blob"`,
  depends on `ImageMetadataRepository`) — exercises TC-WKR-002/004/006/008
  ("object-storage processor").

**Known discrepancy carried into execution (see Production Bug Findings in
`verification-summary.md`):** TC-WKR-002/004/006/008 declare the trigger body literal
`"storageType": "s3"` (pre-migration AWS S3 holdover). `AzureBlobFileProcessingService
.getStorageType()` returns `"azure-blob"`, not `"s3"`. Per `AbstractFileProcessingService
.processImage`, a message is only processed when `message.getStorageType().equals(getStorageType())`;
`"s3" != "azure-blob"` so these four tests hit the storage-type-mismatch branch (treated as
success/ack, no file/DB work performed) instead of the happy-path/boundary/special-input/failure
behavior the spec describes for the object-storage processor. The tests are generated using the
EXACT literal trigger body from the spec (not silently corrected) and the mismatch is reported as a
production bug, not patched away.

## Entry-point trigger mechanism (mandatory adaptation, mock-only infra)

The `infra-decision-table.md` sets every dependency (local/blob storage, message broker, PostgreSQL)
to `mock`; there is no real or testcontainer-backed Azure Service Bus / RabbitMQ broker available in
this environment, and no emulator is wired into the repo for it. Since `@ServiceBusListener` dispatch
cannot be exercised through an actual broker here, the only entry-point-faithful trigger available is:
obtain the real Spring-managed listener bean (`BlobFileProcessingService` /
`AzureBlobFileProcessingService`, autowired from the `ApplicationContext`, not a hand-copied
reimplementation) and invoke its public `processImage(ImageProcessingMessage,
ServiceBusReceivedMessageContext)` method directly, constructing the message by deserializing the
exact JSON body from the test case's Trigger section and passing a Mockito mock of
`ServiceBusReceivedMessageContext` to observe `complete()` vs `deadLetter()`. This is a necessary
adaptation forced by the "mock" decision-table mode (no broker, no emulator) — not a shortcut around
a real/testcontainer dependency that was actually available. The pre-existing unit tests in this
module (`AbstractFileProcessingServiceTest`, `BlobFileProcessingServiceTest`,
`AzureBlobFileProcessingServiceTest`) already establish this exact pattern for this codebase.

## TC → Test Planning Table

| TC ID | Test Location (class → method) | Declared Entry Point | Trigger Mechanism (concrete) | Fixtures Loaded (`Data References`) | Non-mock Deps Touched | Config Source | Cleanup Path |
|---|---|---|---|---|---|---|---|
| TC-WKR-001 | `WorkerMessageProcessingPostMigrationIT.tcWkr001_processImageLocalHappyPath` | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) | Autowired real `BlobFileProcessingService` bean (`@ActiveProfiles("dev")`) `.processImage(msg, mockContext)`, `msg` deserialized from the exact TC-WKR-001 JSON body | `testdata/inputs/sample.jpg` | none (all mock) | `@TempDir` as the local storage root (`BlobContainerClient` mock backed by in-memory blob map rooted at temp dir) | `@TempDir` auto-cleanup; fresh mocks per test |
| TC-WKR-002 | `WorkerMessageProcessingPostMigrationIT.tcWkr002_processImageObjectStorageHappyPath` | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) | Autowired real `AzureBlobFileProcessingService` bean (`@ActiveProfiles("test")`, i.e. non-`dev`) `.processImage(msg, mockContext)`, `msg` deserialized from the exact TC-WKR-002 JSON body (literal `storageType":"s3"`, unmodified) | `testdata/seed-data/image-metadata-seed.json`, `testdata/inputs/sample.jpg` | none (all mock) | `@MockitoBean BlobContainerClient` stubbed per-test; `@MockitoBean ImageMetadataRepository` seeded from the JSON fixture | Fresh `@MockitoBean` stub state reset per test (Mockito resets mock state automatically between `@SpringBootTest` test methods via `reset=NONE` + local `Mockito.reset`/fresh stubbing per test) |
| TC-WKR-003 | `WorkerMessageProcessingPostMigrationIT.tcWkr003_processImageLocalTinyNotUpscaled` | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) | Same as TC-WKR-001, body from TC-WKR-003 | `testdata/inputs/tiny.jpg` | none (all mock) | `@TempDir` | `@TempDir` auto-cleanup |
| TC-WKR-004 | `WorkerMessageProcessingPostMigrationIT.tcWkr004_processImageObjectStoragePortraitAlphaPreserved` | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) | Same as TC-WKR-002, body from TC-WKR-004 (literal `storageType":"s3"`, unmodified) | `testdata/seed-data/image-metadata-seed.json`, `testdata/inputs/sample-portrait.png` | none (all mock) | Same as TC-WKR-002 | Same as TC-WKR-002 |
| TC-WKR-005 | `WorkerMessageProcessingPostMigrationIT.tcWkr005_processImageLocalSkipsOtherStorageType` | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) | Same as TC-WKR-001, body from TC-WKR-005 | none | none (all mock) | `@TempDir` (kept empty) | `@TempDir` auto-cleanup |
| TC-WKR-006 | `WorkerMessageProcessingPostMigrationIT.tcWkr006_processImageObjectStorageUnicodeKey` | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) | Same as TC-WKR-002, body from TC-WKR-006 (literal `storageType":"s3"`, unmodified) | `testdata/inputs/sample-portrait.png` | none (all mock) | Same as TC-WKR-002 | Same as TC-WKR-002 |
| TC-WKR-007 | `WorkerMessageProcessingPostMigrationIT.tcWkr007_processImageLocalSourceMissingDeadLetters` | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) | Same as TC-WKR-001, body from TC-WKR-007 | none | none (all mock) | `@TempDir` (kept empty) | `@TempDir` auto-cleanup |
| TC-WKR-008 | `WorkerMessageProcessingPostMigrationIT.tcWkr008_processImageObjectStorageCorruptSourceDeadLetters` | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) | Same as TC-WKR-002, body from TC-WKR-008 (literal `storageType":"s3"`, unmodified) | `testdata/seed-data/image-metadata-seed.json`, `testdata/inputs/corrupt.jpg` | none (all mock) | Same as TC-WKR-002 | Same as TC-WKR-002 |

All 8 rows: decision table says every dependency is `mock`, so "Non-mock Deps Touched" is `none` for
every TC. `Config Source` for the local-storage tests is a per-test `@TempDir` backing an in-memory
`Map<String, byte[]>` stand-in for blob storage, stubbed onto a Mockito `BlobContainerClient` /
`BlobClient`. For the object-storage tests, `BlobContainerClient`/`BlobClient` and
`ImageMetadataRepository` are Spring `@MockitoBean`s replacing the real Azure SDK client and JPA
repository beans inside the full `@SpringBootTest` context (H2 is configured in
`application.properties` but is not used — the repository bean itself is replaced by a mock, per the
decision table's explicit instruction).

## Pre-Generation Trigger Audit (Step 5 mandatory gate)

| TC ID | Trigger pseudocode | Entry Point Type (from spec) | Violates Step 4 forbidden patterns? |
|---|---|---|---|
| TC-WKR-001 | `blobFileProcessingService.processImage(mapper.readValue(TC_001_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — invokes the real `@Service` listener bean's public entry-point method; no broker available under the `mock` decision table, so direct invocation of the actual production bean (not a reimplementation) is the necessary adaptation documented above |
| TC-WKR-002 | `azureBlobFileProcessingService.processImage(mapper.readValue(TC_002_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation; message body is the unmodified literal from the spec (`storageType":"s3"`) |
| TC-WKR-003 | `blobFileProcessingService.processImage(mapper.readValue(TC_003_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-001 |
| TC-WKR-004 | `azureBlobFileProcessingService.processImage(mapper.readValue(TC_004_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-002 |
| TC-WKR-005 | `blobFileProcessingService.processImage(mapper.readValue(TC_005_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-001 |
| TC-WKR-006 | `azureBlobFileProcessingService.processImage(mapper.readValue(TC_006_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-002 |
| TC-WKR-007 | `blobFileProcessingService.processImage(mapper.readValue(TC_007_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-001 |
| TC-WKR-008 | `azureBlobFileProcessingService.processImage(mapper.readValue(TC_008_BODY, ImageProcessingMessage.class), mockContext)` | Message-queue listener | No — same adaptation as TC-WKR-002 |

All rows: `No`. In every row the system-under-test bean is the real, Spring-managed, fully-wired
production `@Service` (`BlobFileProcessingService` / `AzureBlobFileProcessingService`), obtained via
`@Autowired` from the test's `ApplicationContext` — not a hand-written test double, not a
reimplementation of `processImage`'s business logic, and not a direct call into a lower-level helper
(`downloadOriginal`/`generateThumbnail`/`uploadThumbnail` are exercised transitively through the real
`processImage` call, never invoked standalone by the test). Only the Azure SDK boundary
(`BlobContainerClient`/`BlobClient`) and the JPA repository boundary (`ImageMetadataRepository`) are
mocked, matching the `mock` decision for every dependency row in `infra-decision-table.md`.


---

# Pre-Generation Trigger Audit — web module

# Pre-Generation Trigger Audit — `web` module `*PostMigrationIT`

| TC ID | Trigger pseudocode | Entry Point Type | Violates forbidden patterns? |
|---|---|---|---|
| TC-WEB-001 | `mockMvc.perform(multipart("/storage/upload").file(sampleJpgPart))` | HTTP | No — HTTP test client against the declared endpoint |
| TC-WEB-002 | `mockMvc.perform(multipart("/storage/upload").file(sampleJpgPart))` | HTTP | No |
| TC-WEB-003 | `mockMvc.perform(multipart("/storage/upload").file(emptyBytesPart("empty.jpg")))` | HTTP | No |
| TC-WEB-004 | `testRestTemplate.postForEntity("/storage/upload", oversizedBinMultipartBody, String.class)` (real over-the-wire HTTP, `webEnvironment = RANDOM_PORT`) | HTTP | No |
| TC-WEB-005 | `mockMvc.perform(multipart("/storage/upload").file(tinyJpgPart, filename="../tiny.jpg"))` | HTTP | No |
| TC-WEB-006 | `mockMvc.perform(multipart("/storage/upload").file(samplePortraitPart, filename="테스트 이미지.png"))` | HTTP | No |
| TC-WEB-007 | `testRestTemplate.postForEntity("/storage/upload", tinyJpgMultipartBody, String.class)` (real over-the-wire HTTP, `webEnvironment = RANDOM_PORT`; `serviceBusTemplate.send(...)` stubbed to throw) | HTTP | No |
| TC-WEB-008 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-009 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-010 | `mockMvc.perform(get("/storage"))` | HTTP | No |
| TC-WEB-011 | `mockMvc.perform(get("/storage/view-page/sample.jpg"))` | HTTP | No |
| TC-WEB-012 | `mockMvc.perform(get("/storage/view/sample.jpg"))` | HTTP | No |
| TC-WEB-013 | `mockMvc.perform(get("/storage/view-page/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-014 | `mockMvc.perform(get("/storage/view/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-015 | `mockMvc.perform(post("/storage/delete/{key}", seededKey))` | HTTP | No |
| TC-WEB-016 | `mockMvc.perform(post("/storage/delete/sample.jpg"))` | HTTP | No |
| TC-WEB-017 | `mockMvc.perform(post("/storage/delete/does-not-exist.jpg"))` | HTTP | No |
| TC-WEB-018 | `backupMessageProcessor.processBackupMessage(deserializedMessage, mockServiceBusReceivedMessageContext)` (real `@Autowired` Spring-managed bean, `backup`-profile context) | Message-queue listener | **Documented forced adaptation** — see "Note on TC-WEB-018's trigger" in `post-migration-plan-web.md`. All other avenues (real Service Bus namespace, testcontainer/emulator) are unavailable because the infra-decision-table fixes every dependency to `mock` and no broker/emulator is wired in this repository/environment. The call target is the real, container-managed `@Component` bean's public listener method (not a private helper, not a reimplementation of its logic) with its message argument coming straight from the spec's literal JSON trigger body — this is the closest available approximation to "produce a real event on the declared source" under the fixed mock-only constraint, pre-approved by the task owner rather than self-selected to dodge a real dependency that was otherwise reachable. |

All HTTP rows (TC-WEB-001..017) use a real HTTP test client (`MockMvc` for most cases; `TestRestTemplate` over a real embedded server for TC-WEB-004/TC-WEB-007, which need genuine servlet-container multipart-size enforcement and container-level error-page dispatch that MockMvc's mock dispatch cannot provide — see "Note on the dev-profile real-server split" in `post-migration-plan-web.md`) against the exact path/method declared as the Entry Point in `test-cases.md`, with no internal service/SDK call substituted as the trigger. Only TC-WEB-018 deviates from using an HTTP/real-queue trigger, and that deviation is explicitly documented, not silent.

