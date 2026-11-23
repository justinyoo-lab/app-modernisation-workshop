# Modernization Summary — 006-transform-s3-to-private-blob

## finalStatus
success

## successCriteriaStatus
- passBuild: true
- passUnitTests: true
- generateNewUnitTests: true

## Summary

Migrated the non-dev ("object storage") file-storage path in both the `web` and `worker`
modules from the AWS S3 SDK to Azure Blob Storage, authenticated by Azure Managed Identity,
completing the modernization started in task 005 (which migrated only the dev-profile
local-filesystem path).

### Code changes

**web module**
- Removed `AwsS3Config` (web) and `AwsS3Service` (web).
- Added `AzureBlobService` (`@Profile("!dev")`) implementing `StorageService`, reusing the
  shared `BlobContainerClient` bean (from `BlobStorageConfig`, already provisioned for the
  dev profile in task 005) and injecting `ServiceBusTemplate` + `ImageMetadataRepository`.
- Preserves all non-dev behavior from the frozen baseline (`test-cases.md`):
  - upload creates exactly one `image_metadata` row (`s3Key`, `s3Url`, `filename`,
    `contentType`, `size`), distinct from the dev/local no-metadata path;
  - delete removes the original blob, best-effort removes the thumbnail blob, and removes
    the corresponding `image_metadata` row;
  - list resolves `uploadedAt` from `image_metadata` when a matching row exists, falling back
    to the blob's last-modified timestamp otherwise;
  - the `<uuid>-<filename>` / `<uuid>-<name>_thumbnail.<ext>` key conventions are unchanged.
- Hardened key handling with `BlobKeyValidator` (already introduced in task 005): the raw
  uploaded filename is sanitized *before* the UUID prefix is appended (sanitizing only the
  final concatenated key would let a malicious filename like `../../secret.jpg` be silently
  collapsed to a safe-looking string by path normalization once prefixed — this was caught
  and fixed via a dedicated unit test), closing the CWE-99 (Improper Control of Resource
  Identifiers / Resource Injection) gap flagged by the assessment.
- Storage never exposes Blob objects or generates a SAS URL (time-limited or indefinite):
  bytes are streamed through `S3Controller`'s existing `/storage/view/{key}` endpoint via the
  `StorageService#generateUrl` default, same as the dev path.
- Updated `ImageProcessingMessage`'s `storageType` doc comment to `"azure-blob"` or `"local"`.

**worker module**
- Removed `AwsS3Config` (worker) and `S3FileProcessingService`.
- Added `AzureBlobFileProcessingService` (`@Profile("!dev")`) extending
  `AbstractFileProcessingService`, reusing the shared `BlobContainerClient` bean and
  `ImageMetadataRepository`.
- Preserves the non-dev thumbnail-processing behavior: downloads the original blob,
  generates the thumbnail, uploads it, and updates the matching `image_metadata` row's
  `thumbnailKey`/`thumbnailUrl` (looked up by original `s3Key`).
- `generateUrl()` now returns an app-relative path (`/storage/{key}`) instead of a direct,
  publicly resolvable S3/Blob object URL — the previous S3 implementation exposed a direct
  object URL, which conflicted with the "do not expose Blob objects" requirement; this is
  now consistent with the dev-profile `BlobFileProcessingService`.
- All blob keys (download source, thumbnail destination) are validated through
  `BlobKeyValidator` before being used to address a blob (CWE-99 mitigation).
- Storage-type routing string changed from `"s3"` to `"azure-blob"` in both modules,
  consistently, so Service Bus messages are still routed to the matching
  implementation (verified not to be part of the frozen baseline's literal string
  assertions — baseline only checks `"<configured-storage-type>"` is consistent).

**Dependencies / configuration**
- Removed `software.amazon.awssdk:s3` dependency (and its `dependencyManagement` entry /
  `aws-sdk.version` property) from both `web/pom.xml` and `worker/pom.xml`. No AWS SDK
  dependency remains anywhere in the project.
- Removed all `aws.*` properties (`aws.accessKey(Id)`, `aws.secretKey`, `aws.region`,
  `aws.s3.bucket`) from both modules' `application.properties`.
- No new Azure Blob dependency was required: `spring-cloud-azure-starter-storage-blob` was
  already present from task 005 and is now shared by both the dev and non-dev profiles.
- Updated the `BlobStorageConfig` Javadoc in both modules to reflect that the
  `BlobContainerClient` bean (and its backing private, managed-identity-authenticated
  container) is now shared by both storage profiles, since they are mutually exclusive at
  runtime.

### Scope note (not migrated — out of scope per task description)
No AWS account/data access was performed; this was a pure code/config transform. No S3 data
migration was attempted, and no live AWS or Azure services were contacted at any point
during development or testing.

### Tests

Added/replaced unit tests (JUnit 5 + Mockito, all dependencies mocked — no live Azure/AWS
service, Service Bus namespace, or database is contacted):
- `web/src/test/.../service/AzureBlobServiceTest.java` (16 tests): upload success (blob
  stored, message published, metadata row created), duplicate uploads, empty-file rejection,
  path-traversal filename rejection, `BlobStorageException` wrapped as `IOException`,
  get/delete happy-path and not-found cases, delete thumbnail best-effort tolerance, delete
  leaves unrelated metadata untouched, list resolves `uploadedAt` from metadata or falls back
  to last-modified, list tolerates `BlobStorageException` by returning an empty list, and
  storage-type routing value.
- `worker/src/test/.../service/AzureBlobFileProcessingServiceTest.java` (9 tests): download
  success/not-found/path-traversal-rejection, thumbnail upload + content-type + metadata
  update, metadata left untouched when no match found, thumbnail upload path-traversal
  rejection, `generateUrl` app-relative/no-SAS behavior, and `extractOriginalKey` helper.
- Removed the now-obsolete `AwsS3ServiceMessagingTest.java` (web) and
  `S3FileProcessingServiceTest.java` (worker), which directly mocked the AWS SDK.

### Verification
- `mvnw test` (JDK 25): **BUILD SUCCESS** — web module 62 tests / 0 failures / 0 errors;
  worker module 51 tests / 0 failures / 0 errors.
- Consistency check (`validation-check-consistency` skill): 22 files analyzed, **0 issues**
  (no Critical/Major/Minor findings).
- Completeness check: no remaining `software.amazon.awssdk` / AWS S3 references anywhere in
  source, configuration, or build files (`pom.xml`, `application.properties`, `*.java`).
  Remaining matches for "AwsS3"/"aws.s3" are confined to historical assessment/plan reports
  under `.github/modernize/` and the frozen `test-cases/infra-decision-table.md` files, none
  of which were modified.
- No baseline test artifacts (`test-cases.md`, `testdata/`) or `*PostMigrationIT` files were
  modified.
