# Modernization Summary: 005-transform-dev-local-files-to-private-blob

## finalStatus
**completed**

## successCriteriaStatus
- passBuild: true
- passUnitTests: true
- generateNewUnitTests: true

## Summary

Migrated the Spring `dev` profile's storage backend from local Java NIO filesystem persistence
(a `../storage` directory) to a private Azure Blob Storage container, authenticated via Azure
Managed Identity (passwordless), in both the `web` and `worker` modules. The non-dev AWS S3 path
is untouched and is left for task 006.

### Code changes

**web module**
- Removed `LocalFileStorageService` (local filesystem I/O).
- Added `BlobFileStorageService` (`@Profile("dev")`), implementing `StorageService` against a
  managed-identity-authenticated `BlobContainerClient`: `uploadObject`, `getObject`,
  `deleteObject`, and `listObjects` now operate on Azure Blob Storage blobs instead of local
  files. `getStorageType()` still returns `"local"` so the existing Service Bus
  thumbnail-generation routing (`ImageProcessingMessage.storageType` match in
  `AbstractFileProcessingService`) continues to work unchanged.
- Added `BlobKeyValidator`, a package-private utility that normalizes and validates blob keys
  (upload filenames and the `{key}` path variable used by `S3Controller`), rejecting blank keys,
  relative path traversal (`..`), and absolute paths (Unix leading slash, Windows drive letter,
  UNC share) — mitigating CWE-22, CWE-23, and CWE-36 more thoroughly than the single `".."`
  check the local-file implementation had.
- Added `BlobStorageConfig`, exposing a `BlobContainerClient` bean built from the
  `spring-cloud-azure-starter-storage-blob`-managed `BlobServiceClient`. The container is created
  private (no `PublicAccessType` is ever set) on a best-effort, non-fatal basis if missing, and no
  SAS URL (time-limited or indefinite) is ever generated.
- Added the `spring-cloud-azure-starter-storage-blob` dependency to `web/pom.xml`.
- Added `spring.cloud.azure.storage.blob.endpoint` and `azure.storage.blob.container-name`
  properties (externalized via environment variables, no hardcoded endpoint/container), reusing
  the existing `spring.cloud.azure.credential.managed-identity-enabled` setting shared with
  Service Bus/PostgreSQL.

**worker module**
- Removed `LocalFileProcessingService` (local filesystem I/O).
- Added `BlobFileProcessingService` (`@Profile("dev")`), extending
  `AbstractFileProcessingService`: `downloadOriginal` and `uploadThumbnail` now operate on Azure
  Blob Storage instead of local files. `getStorageType()` stays `"local"`. `generateUrl` returns
  an app-relative path (`/storage/{key}`), consistent with the previous local-storage
  implementation and the requirement to never expose a Blob SAS URL.
- Added `BlobKeyValidator` (mirrors the web module's validator; duplicated per-module since web
  and worker are independent Maven modules with no shared library, consistent with the existing
  per-module `AwsS3Config` duplication pattern).
- Added `BlobStorageConfig`, mirroring the web module's bean/config so a future task 006
  (non-dev AWS S3 → Blob migration) can reuse the same pattern without conflicting.
- Added the `spring-cloud-azure-starter-storage-blob` dependency to `worker/pom.xml` and the same
  `application.properties` additions as the web module.

### Preserved behavior
- Dev-profile uploads still do **not** write an `image_metadata` database row (verified against
  the task 001 baseline and unchanged by this task).
- Upload/list/view/delete/thumbnail behavior is functionally equivalent from the caller's
  perspective (`S3Controller`, `AbstractFileProcessingService`).
- The Service Bus message contract (`ImageProcessingMessage`, `storageType = "local"`) is
  unchanged, so web → worker thumbnail-generation routing still works.
- No existing local files were migrated (out of scope, per task instructions).

### Security
- Addresses CWE-22 / CWE-23 / CWE-36 via `BlobKeyValidator`.
- No public/anonymous blob access; no SAS URLs (time-limited or indefinite) are ever generated.
- Authentication is Azure Managed Identity (passwordless); no account key or connection string is
  stored in code, config, or Git (verified by new `BlobStorageConfigurationTest` in both
  modules).

### Tests added
- `BlobKeyValidatorTest` (web and worker): path/key validation — blank, relative traversal,
  absolute traversal (Unix/Windows/UNC), and valid keys.
- `BlobFileStorageServiceTest` (web): mocked `BlobContainerClient`/`BlobClient`/
  `ServiceBusTemplate` covering upload (including path-traversal rejection and empty-file
  rejection), get (including missing-object `FileNotFoundException`), delete (including missing
  object, missing thumbnail, and thumbnail-deletion failure tolerance), list, and storage-type
  routing compatibility.
- `BlobFileProcessingServiceTest` (worker): retains the original thumbnail-generation tests and
  adds mocked Blob interaction tests for download/upload (including missing-object and
  path-traversal rejection cases).
- `BlobStorageConfigurationTest` (web and worker): verifies no account key/connection
  string/local-storage configuration remains and that managed identity, endpoint, and container
  name are correctly externalized.

### Verification
- Consistency check: 0 Critical, 0 Major, 0 Minor issues (see
  `005-transform-dev-local-files-to-private-blob/consistency-check-report.json`).
- Full Maven Wrapper build (`mvnw clean verify`) succeeds for both `web` and `worker` modules
  with JDK 25.
- All unit tests pass: 0 failures, 0 errors across all suites (90 tests across both modules,
  including the newly added Blob-related tests).
- No real Azure Storage account was contacted; all Blob Storage interactions in tests are
  mocked.
