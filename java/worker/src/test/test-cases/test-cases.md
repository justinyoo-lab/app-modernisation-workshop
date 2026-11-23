# Test Cases

> This document is the **frozen behavioral specification** of the `worker` module's external surface for the migration in scope. It is the source of truth that the `verify-test-baseline` skill uses to generate `*PostMigrationIT` tests against the new implementation. No test code is generated in the baseline phase.

## Metadata

| Field | Value |
|-------|-------|
| Project | assets-manager (Java `worker` module) |
| Module | `worker` |
| Migration Scope | migrate from Java 8 / Spring Boot 2.7.18 / RabbitMQ / PostgreSQL (local) / local files & AWS S3 to Azure (JDK 25, Spring Boot 4.1.2, Azure Database for PostgreSQL Flexible Server, Azure Service Bus, private Azure Blob Storage), targeting Linux Azure Container Apps |
| Created At | 2026-11-22 |
| Status | baseline (frozen) |
| Testing Conventions | JUnit 5 + Mockito (`spring-boot-starter-test`). Existing conventions observed in `worker/src/test/java/.../service/{LocalFileProcessingServiceTest,S3FileProcessingServiceTest}.java`: plain JUnit 5 classes named `<Subject>Test`, `@ExtendWith(MockitoExtension.class)` + `@Mock`/`@InjectMocks` for collaborators, `ReflectionTestUtils` for private-field injection and private-method invocation, `@TempDir` for filesystem fixtures, `org.junit.jupiter.api.Assertions` (`assertEquals`, `assertTrue`, `assertArrayEquals`). New test code produced in `verify-test-baseline` MUST follow these conventions. |

## Existing Test Coverage

`LocalFileProcessingServiceTest` and `S3FileProcessingServiceTest` exercise only internal helper methods (`generateThumbnail`, `downloadOriginal`, `uploadThumbnail`, `getStorageType`, `extractOriginalKey`) called from within `AbstractFileProcessingService.processImage`. Per the create-test-baseline rule that "test cases that exercise only helpers called within an entry point do NOT count toward this requirement", neither existing test class provides end-to-end coverage of the `processImage` listener entry point (no test publishes/consumes a message and observes the ack/nack and final resource state). They are listed here for context but every test case below is new.

| Entry Point | Existing Test (FQ name) | Categories Covered |
|---|---|---|
| (helper only, not the listener entry point) | `com.microsoft.migration.assets.worker.service.LocalFileProcessingServiceTest` | none (internal helper coverage only) |
| (helper only, not the listener entry point) | `com.microsoft.migration.assets.worker.service.S3FileProcessingServiceTest` | none (internal helper coverage only) |

## Entry-Point Inventory

| Entry Point | Type | Source (file:symbol) | Covered by |
|---|---|---|---|
| Listener bound to queue `image-processing`, consuming `ImageProcessingMessage` — local-storage processor (profile: `dev`) | Message-queue listener | `worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java:processImage` (concrete bean: `LocalFileProcessingService`) | TC-WKR-001, TC-WKR-003, TC-WKR-005, TC-WKR-007 |
| Listener bound to queue `image-processing`, consuming `ImageProcessingMessage` — object-storage processor (profile: `!dev`) | Message-queue listener | `worker/src/main/java/com/microsoft/migration/assets/worker/service/AbstractFileProcessingService.java:processImage` (concrete bean: `S3FileProcessingService`) | TC-WKR-002, TC-WKR-004, TC-WKR-006, TC-WKR-008 |

Entry-point type used: `Message-queue listener`.

## Test Cases

### TC-WKR-001 Process image — happy path (local storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-001 |
| Category | happy-path |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) |
| Description | A valid landscape JPEG referenced by an incoming message is downloaded from local storage, a 600px-bounded thumbnail is produced preserving aspect ratio, and the thumbnail is written back to local storage. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "sample.jpg",
  "contentType": "image/jpeg",
  "storageType": "local",
  "size": 2135
}
```

**Preconditions**

- Active Spring profile: `dev`.
- A file `sample.jpg` exists in the local storage directory, byte-identical to `testdata/inputs/sample.jpg` (300x200 opaque JPEG).
- No file `sample_thumbnail.jpg` exists in the local storage directory.

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message after successful processing; no synchronous response is observable.

**Resource Verification**

- A file `sample_thumbnail.jpg` exists in the local storage directory, is a readable JPEG image, with dimensions `300x200` (the 300x200 original is not upscaled, since the thumbnail generator's "do not scale up" guard leaves images already at or below the 600px bound unchanged).
- The message is acknowledged and does not remain available for redelivery on queue `image-processing`.

**Negative Verification**

- No row is created in `image_metadata` (the local-storage processor has no database dependency).
- The original file `sample.jpg` is unchanged (byte-identical to `testdata/inputs/sample.jpg`).

**Data References**

- `testdata/inputs/sample.jpg`

---

### TC-WKR-002 Process image — happy path (object-storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-002 |
| Category | happy-path |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) |
| Description | A valid landscape JPEG referenced by an incoming message is downloaded from the configured object-storage container, a 600px-bounded thumbnail is produced, the thumbnail is uploaded back to the container, and the matching `image_metadata` row is updated with the thumbnail key/url. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "11111111-1111-4111-8111-111111111111-sample.jpg",
  "contentType": "image/jpeg",
  "storageType": "s3",
  "size": 2135
}
```

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Object `11111111-1111-4111-8111-111111111111-sample.jpg` exists in the configured container, byte-identical to `testdata/inputs/sample.jpg`, content-type `image/jpeg`.
- `image_metadata` table pre-populated with the 3 rows from `testdata/seed-data/image-metadata-seed.json` (row 1 has `s3Key = 11111111-1111-4111-8111-111111111111-sample.jpg`, `thumbnailKey IS NULL`).

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message after successful processing; no synchronous response is observable.

**Resource Verification**

- An object `11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg` exists in the container, content-type `image/jpeg`, a readable JPEG image with dimensions `300x200` (the 300x200 original is not upscaled, since the thumbnail generator's "do not scale up" guard leaves images already at or below the 600px bound unchanged).
- The `image_metadata` row with `s3Key = 11111111-1111-4111-8111-111111111111-sample.jpg` now has `thumbnailKey = 11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg` and a non-null `thumbnailUrl`.
- The message is acknowledged and does not remain available for redelivery on queue `image-processing`.

**Negative Verification**

- No additional row is created in `image_metadata`.
- The other 2 seeded rows (`s3Key` ending `-sample-portrait.png` and `-tiny.jpg`) remain unchanged (`thumbnailKey IS NULL`).

**Data References**

- `testdata/seed-data/image-metadata-seed.json`
- `testdata/inputs/sample.jpg`

---

### TC-WKR-003 Process image — thumbnail not upscaled for a sub-600px source (boundary, local storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-003 |
| Category | boundary |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) |
| Description | A source image smaller than the 600px thumbnail bound is not upscaled; the thumbnail retains the original 1x1 dimensions. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "tiny.jpg",
  "contentType": "image/jpeg",
  "storageType": "local",
  "size": 633
}
```

**Preconditions**

- Active Spring profile: `dev`.
- A file `tiny.jpg` exists in the local storage directory, byte-identical to `testdata/inputs/tiny.jpg` (1x1 opaque JPEG).

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message after successful processing.

**Resource Verification**

- A file `tiny_thumbnail.jpg` exists in the local storage directory, is a readable JPEG image, with `width = 1` and `height = 1` (unchanged from the source; no upscaling occurs for images already at or below the 600px bound).
- The message is acknowledged and does not remain available for redelivery on queue `image-processing`.

**Negative Verification**

- No row is created in `image_metadata`.

**Data References**

- `testdata/inputs/tiny.jpg`

---

### TC-WKR-004 Process image — portrait transparent PNG preserves alpha (boundary, object-storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-004 |
| Category | boundary |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) |
| Description | A portrait PNG with an alpha channel is scaled to a 600px-bounded thumbnail on the height axis while preserving transparency and aspect ratio. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "22222222-2222-4222-8222-222222222222-sample-portrait.png",
  "contentType": "image/png",
  "storageType": "s3",
  "size": 1076
}
```

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Object `22222222-2222-4222-8222-222222222222-sample-portrait.png` exists in the configured container, byte-identical to `testdata/inputs/sample-portrait.png` (150x300 PNG with alpha channel).
- `image_metadata` table pre-populated with the 3 rows from `testdata/seed-data/image-metadata-seed.json` (row 2 has `s3Key = 22222222-2222-4222-8222-222222222222-sample-portrait.png`, `thumbnailKey IS NULL`).

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message after successful processing.

**Resource Verification**

- An object `22222222-2222-4222-8222-222222222222-sample-portrait_thumbnail.png` exists in the container, content-type `image/png`, a readable PNG image with dimensions `150x300` (the 150x300 original is not upscaled, since the thumbnail generator's "do not scale up" guard leaves images already at or below the 600px bound unchanged), and the image's color model reports an alpha channel.
- The `image_metadata` row with `s3Key = 22222222-2222-4222-8222-222222222222-sample-portrait.png` now has `thumbnailKey = 22222222-2222-4222-8222-222222222222-sample-portrait_thumbnail.png` and a non-null `thumbnailUrl`.

**Negative Verification**

- The other 2 seeded rows remain unchanged.

**Data References**

- `testdata/seed-data/image-metadata-seed.json`
- `testdata/inputs/sample-portrait.png`

---

### TC-WKR-005 Process image — message for the other storage type is skipped (special-input, local storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-005 |
| Category | special-input |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) |
| Description | When the local-storage processor receives a message whose `storageType` does not match its own (`local`), it skips processing entirely and still acknowledges the message successfully, without reading or writing any file. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "11111111-1111-4111-8111-111111111111-sample.jpg",
  "contentType": "image/jpeg",
  "storageType": "s3",
  "size": 2135
}
```

**Preconditions**

- Active Spring profile: `dev` (only the local-storage processor bean is present).
- Local storage directory is empty (the key referenced in the message does not exist locally, which must not matter since the message is skipped before any file access).

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message without processing it (storage-type mismatch is treated as success, not an error).

**Resource Verification**

- The message is acknowledged and does not remain available for redelivery on queue `image-processing`.

**Negative Verification**

- No file is created in the local storage directory (in particular, no `11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg` is created).
- No row is created in `image_metadata`.

**Data References**

- none

---

### TC-WKR-006 Process image — unicode key with embedded space (special-input, object-storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-006 |
| Category | special-input |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) |
| Description | A message key containing non-ASCII Unicode characters and a space is processed identically to an ASCII key: the thumbnail key is derived by the same suffix-insertion rule and both the thumbnail object and the metadata row use the Unicode key verbatim. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "테스트 이미지.png",
  "contentType": "image/png",
  "storageType": "s3",
  "size": 1076
}
```

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Object `테스트 이미지.png` exists in the configured container, byte-identical to `testdata/inputs/sample-portrait.png`.
- `image_metadata` table contains one row with `s3Key = 테스트 이미지.png`, `thumbnailKey IS NULL` (otherwise matching the shape of the rows in `testdata/seed-data/image-metadata-seed.json`).

**Expected Response**

`none (fire-and-forget)` — the listener acknowledges the message after successful processing.

**Resource Verification**

- An object `테스트 이미지_thumbnail.png` exists in the container, content-type `image/png`, a readable PNG image with dimensions `150x300` (the 150x300 original is not upscaled, since the thumbnail generator's "do not scale up" guard leaves images already at or below the 600px bound unchanged).
- The `image_metadata` row with `s3Key = 테스트 이미지.png` now has `thumbnailKey = 테스트 이미지_thumbnail.png` and a non-null `thumbnailUrl`.

**Negative Verification**

- No additional row is created in `image_metadata`.

**Data References**

- `testdata/inputs/sample-portrait.png`

---

### TC-WKR-007 Process image — source file missing (failure, local storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-007 |
| Category | failure |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, local-storage processor (profile `dev`) |
| Description | When the file referenced by the message key does not exist in local storage, the download step fails, no thumbnail is produced, and the message is rejected without requeue (routed to the dead-letter path) rather than acknowledged. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "missing.jpg",
  "contentType": "image/jpeg",
  "storageType": "local",
  "size": 2135
}
```

**Preconditions**

- Active Spring profile: `dev`.
- Local storage directory is empty (no file named `missing.jpg`).

**Expected Response**

`none (fire-and-forget)` — the listener rejects the message (`basicNack` with `requeue=false`) after the download step throws; no synchronous response is observable.

**Resource Verification**

- The message is not redelivered on queue `image-processing` and is routed to the configured dead-letter path (it is nacked with `requeue=false`, not left pending or requeued).

**Negative Verification**

- No file `missing_thumbnail.jpg` (or any new file) is created in the local storage directory.
- No row is created in `image_metadata`.

**Data References**

- none

---

### TC-WKR-008 Process image — corrupt source image (failure, object-storage processor)

| Field | Value |
|-------|-------|
| ID | TC-WKR-008 |
| Category | failure |
| Entry Point Type | Message-queue listener |
| Entry Point | Listener bound to queue `image-processing`, object-storage processor (profile `!dev`) |
| Description | When the object referenced by the message key exists but is not a decodable image, thumbnail generation fails, no thumbnail is uploaded, the metadata row is left untouched, and the message is rejected without requeue. |

**Trigger**

Publish one message to queue `image-processing` with body:

```json
{
  "key": "33333333-3333-4333-8333-333333333333-tiny.jpg",
  "contentType": "image/jpeg",
  "storageType": "s3",
  "size": 74
}
```

**Preconditions**

- Active Spring profile: non-`dev` (object-storage profile).
- Object `33333333-3333-4333-8333-333333333333-tiny.jpg` exists in the configured container with content byte-identical to `testdata/inputs/corrupt.jpg` (not a valid image; 74 bytes of plain text).
- `image_metadata` table pre-populated with the 3 rows from `testdata/seed-data/image-metadata-seed.json` (row 3 has `s3Key = 33333333-3333-4333-8333-333333333333-tiny.jpg`, `thumbnailKey IS NULL`).

**Expected Response**

`none (fire-and-forget)` — the listener rejects the message (`basicNack` with `requeue=false`) after `ImageIO.read` returns `null` and thumbnail generation throws; no synchronous response is observable.

**Resource Verification**

- The message is not redelivered on queue `image-processing` and is routed to the configured dead-letter path.

**Negative Verification**

- No object `33333333-3333-4333-8333-333333333333-tiny_thumbnail.jpg` (or any new object) is created in the container.
- The `image_metadata` row with `s3Key = 33333333-3333-4333-8333-333333333333-tiny.jpg` remains with `thumbnailKey IS NULL` and `thumbnailUrl IS NULL`.
- The other 2 seeded rows remain unchanged.

**Data References**

- `testdata/seed-data/image-metadata-seed.json`
- `testdata/inputs/corrupt.jpg`

---

## Required Field Checklist (Freeze Gate)

- [x] **ID** unique, formatted `TC-WKR-NNN`.
- [x] **Category** is one of `happy-path`, `boundary`, `special-input`, `failure`.
- [x] **Entry Point Type** matches the catalog type (`Message-queue listener`).
- [x] **Entry Point** is an exact production-code identifier (queue name + consuming method + concrete bean per profile).
- [x] **Trigger** is concrete enough to construct the call mechanically (full message body given).
- [x] **Preconditions** enumerated; all referenced seed data exists under `testdata/`.
- [x] **Expected Response** specifies `none (fire-and-forget)` plus the ack/nack outcome in every case.
- [x] **Resource Verification** has at least one bullet OR explicit `none` with justification.
- [x] **Negative Verification** present for every `failure` case and every "skip / no-op" outcome (TC-WKR-005, TC-WKR-007, TC-WKR-008).
- [x] **Data References** complete; every path exists under `testdata/`.

## Coverage Gate

- [x] Every entry point in the Entry-Point Inventory appears as the `Entry Point` of at least one `happy-path` case.
- [x] Every entry point in the Entry-Point Inventory appears as the `Entry Point` of at least one `failure` case.
- [x] Each entry point covers all four buckets (`happy-path`, `boundary`, `special-input`, `failure`).
- [x] Entity examples use 2–5 representative records (3 seeded `image_metadata` rows / storage objects used throughout).

## Banned Phrasings — Self-Check

Reviewed: no instances of "should return a reasonable error", "behaves as expected", "approximately N items", "etc.", or un-named resource/state assertions remain in this document.
