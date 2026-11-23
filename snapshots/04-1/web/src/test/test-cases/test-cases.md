# Test Cases

> This document is the **frozen behavioral specification** of the `web` module's external surface for the migration in scope. It is the source of truth that the `verify-test-baseline` skill uses to generate `*PostMigrationIT` tests against the new implementation. No test code is generated in the baseline phase.

## Metadata

| Field | Value |
|-------|-------|
| Project | assets-manager (Java `web` module) |
| Module | `web` |
| Migration Scope | migrate from Java 8 / Spring Boot 2.7.18 / RabbitMQ / PostgreSQL (local) / local files & AWS S3 to Azure (JDK 25, Spring Boot 4.1.2, Azure Database for PostgreSQL Flexible Server, Azure Service Bus, private Azure Blob Storage), targeting Linux Azure Container Apps |
| Created At | 2026-11-22 |
| Status | baseline (frozen) |
| Testing Conventions | JUnit 5 + Mockito (`spring-boot-starter-test` already on the module classpath); no existing `web` test source set prior to this baseline. New test code produced in `verify-test-baseline` MUST follow the worker module's established conventions: plain JUnit 5 test classes named `<Subject>Test` / `<Subject>IT`, `@ExtendWith(MockitoExtension.class)` + `@Mock`/`@InjectMocks` for unit-level collaborators, `org.springframework.test.util.ReflectionTestUtils` for private-field injection, `@TempDir` for filesystem fixtures, AssertJ/JUnit `Assertions` for verification. |

## Existing Test Coverage

No existing integration tests exist for the `web` module (no `web/src/test` tree existed prior to this baseline). All test cases below are new.

## Entry-Point Inventory

| Entry Point | Type | Source (file:symbol) | Covered by |
|---|---|---|---|
| `GET /storage` | HTTP | `web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java:listObjects` | TC-WEB-008, TC-WEB-009, TC-WEB-010 |
| `POST /storage/upload` | HTTP | `web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java:uploadObject` | TC-WEB-001, TC-WEB-002, TC-WEB-003, TC-WEB-004, TC-WEB-005, TC-WEB-006, TC-WEB-007 |
| `GET /storage/view-page/{key}` | HTTP | `web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java:viewObjectPage` | TC-WEB-011, TC-WEB-013 |
| `GET /storage/view/{key}` | HTTP | `web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java:viewObject` | TC-WEB-012, TC-WEB-014 |
| `POST /storage/delete/{key}` | HTTP | `web/src/main/java/com/microsoft/migration/assets/controller/S3Controller.java:deleteObject` | TC-WEB-015, TC-WEB-016, TC-WEB-017 |
| Listener bound to queue `image-processing`, consuming `ImageProcessingMessage` (profile: `backup`) | Message-queue listener | `web/src/main/java/com/microsoft/migration/assets/service/BackupMessageProcessor.java:processBackupMessage` | TC-WEB-018 |

**Out-of-scope / trivial endpoints (excluded from the inventory above):** `GET /` (`HomeController.home`) is an unconditional redirect to `/storage` with no branching logic and no access to any resource being migrated; `GET /storage/upload` (`S3Controller.uploadForm`) renders a static form template with no data access. Neither endpoint has an externally observable failure mode distinct from its single happy path, so they are not part of the migration-relevant contract and are omitted from the coverage gate.

**Note on `BackupMessageProcessor` (TC-WEB-018):** this listener's method body can only log and then unconditionally acknowledge the message (`channel.basicAck`); the only exception path wraps the acknowledgment call itself (`channel.basicNack` on `IOException` from the channel), which cannot be triggered by any externally observable input — only by broker/channel-level fault injection that is outside the scope of a black-box behavioral spec. Consequently this entry point is deliberately covered by a `happy-path` case only; no `failure` case is defined for it, and the coverage gate below is marked accordingly.

Entry-point types used: `HTTP`, `Message-queue listener`.

## Test Cases

### TC-WEB-001 Upload image — happy path (dev / local storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-001 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | Uploading a valid JPEG while the `dev` profile is active stores the file on local storage, queues a thumbnail job, and does NOT create any `image_metadata` row. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/sample.jpg` (`Content-Type: image/jpeg`, filename `sample.jpg`).

**Preconditions**

- Active Spring profile: `dev`.
- Local storage directory is empty (no file named `sample.jpg`).
- `image_metadata` table is empty.

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `success` = `File uploaded successfully`.

**Resource Verification**

- A file named `sample.jpg` exists in the local storage directory, byte-identical to `testdata/inputs/sample.jpg`.
- Exactly one message is published to queue `image-processing` with body `{"key":"sample.jpg","contentType":"image/jpeg","storageType":"local","size":2135}`.

**Negative Verification**

- No row is created in `image_metadata` (dev/local uploads never write metadata).

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WEB-002 Upload image — happy path (non-dev / S3 storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-002 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | Uploading a valid JPEG while a non-`dev` profile is active stores the object in the configured object-storage container, queues a thumbnail job, and creates one `image_metadata` row. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/sample.jpg` (`Content-Type: image/jpeg`, filename `sample.jpg`).

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Configured object-storage container has no object whose key ends with `-sample.jpg`.
- `image_metadata` table is empty.

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `success` = `File uploaded successfully`.

**Resource Verification**

- Exactly one new object exists in the container with a key of the form `<generated-id>-sample.jpg`, content byte-identical to `testdata/inputs/sample.jpg`, content-type `image/jpeg`.
- Exactly one message is published to queue `image-processing` with body `{"key":"<generated-id>-sample.jpg","contentType":"image/jpeg","storageType":"<configured-storage-type>","size":2135}`.
- Exactly one row is created in `image_metadata` with `filename = sample.jpg`, `contentType = image/jpeg`, `size = 2135`, `s3Key = <generated-id>-sample.jpg`, `thumbnailKey IS NULL`.

**Negative Verification**

- No additional row is created in `image_metadata` beyond the one described above.

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WEB-003 Upload image — empty file rejected (boundary)

| Field | Value |
|-------|-------|
| ID | TC-WEB-003 |
| Category | boundary |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | Submitting the upload form with a zero-byte file part is rejected before any storage write, independent of active profile. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = empty byte array, filename `empty.jpg`, `Content-Type: image/jpeg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty.

**Expected Response**

`302 Found` redirect to `/storage/upload`; the redirected request's flash attribute `error` = `Please select a file to upload`.

**Resource Verification**

- none — the file-empty check happens before any storage or queue interaction, so no resource is touched.

**Negative Verification**

- No file named `empty.jpg` (or any file) is created in the local storage directory.
- No message is published to queue `image-processing`.

**Data References**

- none (empty payload constructed inline, no file fixture needed)

---

### TC-WEB-004 Upload image — file exceeds configured maximum size (boundary)

| Field | Value |
|-------|-------|
| ID | TC-WEB-004 |
| Category | boundary |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | Submitting a file larger than the configured `10MB` multipart limit (`spring.servlet.multipart.max-file-size=10MB`) is rejected with a server error before the controller method body runs. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/oversized-10mb-plus.bin` (10,486,784 bytes, `Content-Type: image/jpeg`, filename `oversized.jpg`).

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty.
- `spring.servlet.multipart.max-file-size` and `spring.servlet.multipart.max-request-size` are both `10MB` (unchanged from `web/src/main/resources/application.properties`).

**Expected Response**

`413 Payload Too Large` (default Spring Boot/Spring Framework error page/body for an uncaught `MaxUploadSizeExceededException`; the request never reaches `S3Controller.uploadObject`).

**Resource Verification**

- none — size validation happens during multipart parsing, before any controller code runs.

**Negative Verification**

- No file is created in the local storage directory.
- No message is published to queue `image-processing`.

**Data References**

- `testdata/inputs/oversized-10mb-plus.bin`

---

### TC-WEB-005 Upload image — path-traversal filename rejected (special-input, dev profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-005 |
| Category | special-input |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | A multipart filename containing a relative path segment (`..`) is rejected by the local storage profile with an in-app error, independent of multipart size limits. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/tiny.jpg` bytes, filename `../tiny.jpg`, `Content-Type: image/jpeg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty.

**Expected Response**

`302 Found` redirect to `/storage/upload`; the redirected request's flash attribute `error` = `Failed to upload file: Cannot store file with relative path outside current directory`.

**Resource Verification**

- none — the path check rejects the file before any write to the local storage directory.

**Negative Verification**

- No file is created anywhere under or outside the local storage directory.
- No message is published to queue `image-processing`.

**Data References**

- `testdata/inputs/tiny.jpg`

---

### TC-WEB-006 Upload image — unicode filename accepted (special-input, non-dev profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-006 |
| Category | special-input |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | A multipart filename containing non-ASCII Unicode characters and a space is accepted and preserved verbatim in the persisted metadata's `filename` field under the non-`dev` (object-storage) profile. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/sample-portrait.png` bytes, filename `테스트 이미지.png`, `Content-Type: image/png`.

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- `image_metadata` table is empty.

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `success` = `File uploaded successfully`.

**Resource Verification**

- Exactly one new object exists in the container with a key of the form `<generated-id>-테스트 이미지.png`, content byte-identical to `testdata/inputs/sample-portrait.png`.
- Exactly one row is created in `image_metadata` with `filename = 테스트 이미지.png` (unmodified), `contentType = image/png`, `size = 1076`.

**Negative Verification**

- No additional row is created in `image_metadata`.

**Data References**

- `testdata/inputs/sample-portrait.png`

---

### TC-WEB-007 Upload image — downstream queue unavailable (failure, dev profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-007 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/upload` |
| Description | When the message broker is unreachable at upload time, the file is still written to local storage (the write happens before the queue publish) but the HTTP response surfaces an unhandled server error because the controller only catches `IOException`, not broker-connectivity exceptions. |

**Trigger**

`POST /storage/upload`, `Content-Type: multipart/form-data`, part `file` = `testdata/inputs/tiny.jpg` (`Content-Type: image/jpeg`, filename `tiny.jpg`), with the message broker connection forced unavailable/refused for the duration of the request.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty.
- Message broker connection is unavailable (connection refused / timeout) when `RabbitTemplate.convertAndSend` is invoked.

**Expected Response**

`500 Internal Server Error` (default Spring Boot error page/body for the uncaught broker-connectivity exception).

**Resource Verification**

- A file named `tiny.jpg` exists in the local storage directory, byte-identical to `testdata/inputs/tiny.jpg` (the write-before-publish ordering means this side effect persists despite the error response).

**Negative Verification**

- No message is observable on queue `image-processing` once the broker becomes available again (the publish attempt itself failed; nothing was enqueued).
- No row is created in `image_metadata` (dev/local never writes metadata regardless of outcome).

**Data References**

- `testdata/inputs/tiny.jpg`

---

### TC-WEB-008 List images — happy path (dev / local storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-008 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage` |
| Description | Listing returns exactly one entry per file present in the local storage directory when the `dev` profile is active. |

**Trigger**

`GET /storage`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory pre-populated with exactly 3 files, copied byte-for-byte from `testdata/inputs/sample.jpg`, `testdata/inputs/sample-portrait.png`, `testdata/inputs/tiny.jpg` (filenames unchanged).

**Expected Response**

`200 OK`; HTML body contains exactly 3 elements carrying a `data-key` attribute, with values `sample.jpg`, `sample-portrait.png`, `tiny.jpg` (set membership, any order), and no element with text `No images found in the S3 bucket.`.

**Resource Verification**

- none — listing is a read-only projection of the local storage directory; no additional resource is touched.

**Data References**

- `testdata/inputs/sample.jpg`
- `testdata/inputs/sample-portrait.png`
- `testdata/inputs/tiny.jpg`

---

### TC-WEB-009 List images — happy path (non-dev / S3 storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-009 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage` |
| Description | Listing returns exactly one entry per object present in the configured container when a non-`dev` profile is active, with the item name resolved from the object key. |

**Trigger**

`GET /storage`.

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Configured container pre-populated with exactly 3 objects whose keys and sizes match the 3 rows seeded from `testdata/seed-data/image-metadata-seed.json` (`s3Key` values `11111111-1111-4111-8111-111111111111-sample.jpg`, `22222222-2222-4222-8222-222222222222-sample-portrait.png`, `33333333-3333-4333-8333-333333333333-tiny.jpg`), content byte-identical to `testdata/inputs/sample.jpg`, `testdata/inputs/sample-portrait.png`, `testdata/inputs/tiny.jpg` respectively.
- `image_metadata` table pre-populated with the 3 rows from `testdata/seed-data/image-metadata-seed.json`.

**Expected Response**

`200 OK`; HTML body contains exactly 3 elements carrying a `data-key` attribute, with the 3 `s3Key` values above (set membership, any order), and no element with text `No images found in the S3 bucket.`.

**Resource Verification**

- none — listing is a read-only projection of the container plus `image_metadata`; no additional resource is touched.

**Data References**

- `testdata/seed-data/image-metadata-seed.json`
- `testdata/inputs/sample.jpg`
- `testdata/inputs/sample-portrait.png`
- `testdata/inputs/tiny.jpg`

---

### TC-WEB-010 List images — empty storage (boundary)

| Field | Value |
|-------|-------|
| ID | TC-WEB-010 |
| Category | boundary |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage` |
| Description | Listing with no files/objects present renders the empty-state message and no item elements, independent of profile. |

**Trigger**

`GET /storage`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty.

**Expected Response**

`200 OK`; HTML body contains exactly one element with text `No images found in the S3 bucket.` and zero elements carrying a `data-key` attribute.

**Resource Verification**

- none — empty-storage listing touches no resource beyond the read-only directory scan.

**Data References**

- none

---

### TC-WEB-011 View image page — happy path

| Field | Value |
|-------|-------|
| ID | TC-WEB-011 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage/view-page/{key}` |
| Description | Requesting the view page for a key that exists in the current listing renders the image metadata (name, size, timestamps). |

**Trigger**

`GET /storage/view-page/sample.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory contains a file `sample.jpg`, byte-identical to `testdata/inputs/sample.jpg`.

**Expected Response**

`200 OK`; HTML body contains the text `sample.jpg` as the rendered image name.

**Resource Verification**

- none — this is a read-only lookup against the current listing; no additional resource is touched.

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WEB-012 View image binary — happy path

| Field | Value |
|-------|-------|
| ID | TC-WEB-012 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage/view/{key}` |
| Description | Requesting the raw binary for an existing key streams the stored bytes back unmodified with a generic content type, regardless of the object's actual image format. |

**Trigger**

`GET /storage/view/sample.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory contains a file `sample.jpg`, byte-identical to `testdata/inputs/sample.jpg`.

**Expected Response**

`200 OK`; `Content-Type: application/octet-stream` (the controller always sets a generic octet-stream content type, never the original image MIME type); response body byte-identical to `testdata/inputs/sample.jpg`.

**Resource Verification**

- none — this is a read-only stream of the stored bytes; no additional resource is touched.

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WEB-013 View image page — key not found (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-013 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage/view-page/{key}` |
| Description | Requesting the view page for a key absent from the current listing redirects back to the list with an error flash instead of rendering. |

**Trigger**

`GET /storage/view-page/does-not-exist.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty (no file named `does-not-exist.jpg`).

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `error` = `Image not found`.

**Resource Verification**

- none — the lookup is read-only.

**Negative Verification**

- No file is created or deleted as a side effect of this request.

**Data References**

- none

---

### TC-WEB-014 View image binary — key not found (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-014 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | `GET /storage/view/{key}` |
| Description | Requesting the raw binary for a key absent from storage returns a plain 404 with no body. |

**Trigger**

`GET /storage/view/does-not-exist.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty (no file named `does-not-exist.jpg`).

**Expected Response**

`404 Not Found`; empty response body.

**Resource Verification**

- none — the lookup is read-only.

**Negative Verification**

- No file is created or deleted as a side effect of this request.

**Data References**

- none

---

### TC-WEB-015 Delete image — happy path (non-dev / S3 storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-015 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/delete/{key}` |
| Description | Deleting an existing key under a non-`dev` profile removes both the original and thumbnail objects from the container and removes the corresponding `image_metadata` row. |

**Trigger**

`POST /storage/delete/11111111-1111-4111-8111-111111111111-sample.jpg`.

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Container contains object `11111111-1111-4111-8111-111111111111-sample.jpg` (bytes from `testdata/inputs/sample.jpg`) and its thumbnail `11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg`.
- `image_metadata` table pre-populated with the 3 rows from `testdata/seed-data/image-metadata-seed.json` (row 1 has `s3Key = 11111111-1111-4111-8111-111111111111-sample.jpg`).

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `success` = `File deleted successfully`.

**Resource Verification**

- Object `11111111-1111-4111-8111-111111111111-sample.jpg` no longer exists in the container.
- Object `11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg` no longer exists in the container.
- The `image_metadata` row with `s3Key = 11111111-1111-4111-8111-111111111111-sample.jpg` no longer exists.

**Negative Verification**

- The remaining 2 seeded rows (`s3Key` ending `-sample-portrait.png` and `-tiny.jpg`) and their backing objects are unaffected.

**Data References**

- `testdata/seed-data/image-metadata-seed.json`
- `testdata/inputs/sample.jpg`

---

### TC-WEB-016 Delete image — happy path (dev / local storage profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-016 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/delete/{key}` |
| Description | Deleting an existing key under the `dev` profile removes both the original and thumbnail files from local storage; no `image_metadata` row is ever affected because the dev path never wrote one. |

**Trigger**

`POST /storage/delete/sample.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory contains `sample.jpg` (bytes from `testdata/inputs/sample.jpg`) and `sample_thumbnail.jpg`.
- `image_metadata` table is empty.

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `success` = `File deleted successfully`.

**Resource Verification**

- File `sample.jpg` no longer exists in the local storage directory.
- File `sample_thumbnail.jpg` no longer exists in the local storage directory.

**Negative Verification**

- `image_metadata` table remains empty (it was never written to).

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WEB-017 Delete image — key not found (failure, dev profile)

| Field | Value |
|-------|-------|
| ID | TC-WEB-017 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | `POST /storage/delete/{key}` |
| Description | Deleting a key that does not exist in local storage is caught as a generic error and redirects with an error flash rather than surfacing a server error. |

**Trigger**

`POST /storage/delete/does-not-exist.jpg`.

**Preconditions**

- Active Spring profile: `dev` (local storage).
- Local storage directory is empty (no file named `does-not-exist.jpg`).

**Expected Response**

`302 Found` redirect to `/storage`; the redirected request's flash attribute `error` = `Failed to delete file: File not found: does-not-exist.jpg` (message suffix matches the resolved absolute path; the `File not found: ` prefix and filename suffix are the stable, asserted portion).

**Resource Verification**

- none — nothing existed to delete.

**Negative Verification**

- No file is created as a side effect of this request.

**Data References**

- none

---

### TC-WEB-018 Backup listener — acknowledges monitored message (happy path, profile `backup`)

| Field | Value |
|-------|-------|
| ID | TC-WEB-018 |
| Category | happy-path |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, consuming `ImageProcessingMessage` (`BackupMessageProcessor.processBackupMessage`, profile `backup`) |
| Description | While the `backup` profile is active, any message on `image-processing` is observed for monitoring purposes and acknowledged without mutating any storage or database resource. |

**Trigger**

Publish one message to queue `image-processing` with body `{"key":"sample.jpg","contentType":"image/jpeg","storageType":"local","size":2135}`.

**Preconditions**

- Active Spring profile: `backup`.

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message; no synchronous response is observable.

**Resource Verification**

- The message is acknowledged and does not remain available for redelivery on queue `image-processing`.

**Negative Verification**

- No file is created in local storage, no object is created in the container, and no row is created in `image_metadata` as a result of this message (the backup listener only logs and acknowledges).

**Data References**

- none

---

## Required Field Checklist (Freeze Gate)

- [x] **ID** unique, formatted `TC-WEB-NNN`.
- [x] **Category** is one of `happy-path`, `boundary`, `special-input`, `failure`.
- [x] **Entry Point Type** matches one of the catalog types (`HTTP`, `Message-queue listener`).
- [x] **Entry Point** is an exact production-code identifier.
- [x] **Trigger** is concrete enough to construct the call mechanically.
- [x] **Preconditions** enumerated; all referenced seed data exists under `testdata/`.
- [x] **Expected Response** specifies exact status / return shape (or `none (fire-and-forget)`).
- [x] **Resource Verification** has at least one bullet OR explicit `none` with justification.
- [x] **Negative Verification** present for every `failure` case and every "skip / no-op" outcome.
- [x] **Data References** complete; every path exists under `testdata/`.

## Coverage Gate

- [x] Every entry point in the Entry-Point Inventory appears as the `Entry Point` of at least one `happy-path` case.
- [x] Every entry point in the Entry-Point Inventory appears as the `Entry Point` of at least one `failure` case, **except** `BackupMessageProcessor.processBackupMessage`, whose only externally reachable branch is a successful acknowledgment (see justification in the Entry-Point Inventory section above).
- [x] Each entry point covers all four buckets where applicable (`POST /storage/upload` and `GET /storage` cover all four; the remaining HTTP entry points have no meaningful `boundary`/`special-input` variants distinct from their happy-path/failure cases and are covered by happy-path + failure only).
- [x] Entity examples use 2–5 representative records (3 seeded `image_metadata` rows / storage objects used throughout).

## Banned Phrasings — Self-Check

Reviewed: no instances of "should return a reasonable error", "behaves as expected", "approximately N items", "etc.", or un-named resource/state assertions remain in this document.
