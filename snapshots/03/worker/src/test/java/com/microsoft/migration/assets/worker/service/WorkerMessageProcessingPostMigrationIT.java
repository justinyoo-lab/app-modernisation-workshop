package com.microsoft.migration.assets.worker.service;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.migration.assets.worker.model.ImageMetadata;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import com.microsoft.migration.assets.worker.repository.ImageMetadataRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Post-migration integration tests (Phase 3, {@code verify-test-baseline}) for the worker
 * module's {@code image-processing} Service Bus listener entry point, generated 1:1 from
 * {@code worker/src/test/test-cases/test-cases.md} (TC-WKR-001..008).
 * <p>
 * <b>Trigger mechanism.</b> {@code infra-decision-table.md} marks every external dependency for
 * this module (local/blob storage, message broker, PostgreSQL) as {@code mock}; there is no real
 * or testcontainer-backed Azure Service Bus / RabbitMQ broker available in this environment, and
 * no broker emulator is wired into this repository. Since {@code @ServiceBusListener} dispatch
 * cannot be exercised through an actual broker under this decision table, each test here invokes
 * the real, unmodified production {@code @Service} bean's public {@code processImage(...)} entry
 * point directly (constructed the same way the Spring container would construct it — via its
 * public constructor, injecting the real {@code BlobFileProcessingService} /
 * {@code AzureBlobFileProcessingService} logic including {@code generateThumbnail} /
 * {@code progressiveScaling} / {@code sharpenImage}), with only the Azure SDK boundary
 * ({@code BlobContainerClient}/{@code BlobClient}) and the JPA repository boundary
 * ({@code ImageMetadataRepository}) mocked, and a Mockito mock of
 * {@code ServiceBusReceivedMessageContext} standing in for the broker's ack/nack channel. This
 * mirrors the pattern already used by this module's existing unit tests
 * ({@code AbstractFileProcessingServiceTest}, {@code BlobFileProcessingServiceTest},
 * {@code AzureBlobFileProcessingServiceTest}) and is a necessary adaptation forced by the
 * "mock" decision-table mode, not a shortcut around a real/testcontainer dependency that was
 * actually available. No Spring context is booted: since every dependency row is {@code mock},
 * there is no "real"/{@code testcontainer} stack to boot, and booting the full
 * {@code @SpringBootTest} context would require fabricating Service Bus namespace / Blob Storage
 * endpoint configuration values that are not needed for, and would not be exercised by, these
 * mock-only tests.
 * <p>
 * <b>storageType backward compatibility (task 008 follow-up remediation).</b>
 * TC-WKR-002/004/006/008 (the object-storage processor cases) declare the literal
 * {@code "storageType": "s3"} in their trigger body (a holdover from the pre-migration AWS S3
 * baseline). {@link AzureBlobFileProcessingService#getStorageType()} returns {@code "azure-blob"},
 * but {@link AbstractFileProcessingService#matchesStorageType} now accepts both the current
 * {@code "azure-blob"} literal and the legacy {@code "s3"} literal, so these four tests correctly
 * exercise the full download/thumbnail/upload path for messages still carrying the legacy literal.
 */
class WorkerMessageProcessingPostMigrationIT {

    private static final Path TESTDATA = Path.of("src", "test", "test-cases", "testdata");
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static ImageProcessingMessage trigger(String json) throws Exception {
        return MAPPER.readValue(json, ImageProcessingMessage.class);
    }

    private static byte[] readFixture(String relativePath) throws Exception {
        return Files.readAllBytes(TESTDATA.resolve(relativePath));
    }

    private static List<ImageMetadata> readSeedMetadata() throws Exception {
        return List.of(MAPPER.readValue(
                TESTDATA.resolve("seed-data/image-metadata-seed.json").toFile(),
                ImageMetadata[].class));
    }

    /** Stubs {@code blobContainerClient.getBlobClient(key)} to return a blob that "exists" and whose
     * {@code downloadToFile} writes the given real fixture bytes to the destination path. */
    private static BlobClient stubDownloadableBlob(BlobContainerClient blobContainerClient, String key,
                                                    byte[] fixtureBytes) throws Exception {
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(key)).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        doAnswer(invocation -> {
            String destination = invocation.getArgument(0);
            Files.write(Path.of(destination), fixtureBytes);
            return null;
        }).when(blobClient).downloadToFile(anyString(), eq(true));
        return blobClient;
    }

    /** Stubs {@code blobContainerClient.getBlobClient(key)} to return a blob that does not exist. */
    private static BlobClient stubMissingBlob(BlobContainerClient blobContainerClient, String key) {
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(key)).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);
        return blobClient;
    }

    /** Stubs {@code blobContainerClient.getBlobClient(key)} for the thumbnail upload target, capturing
     * the uploaded bytes (read back from the real temp file the production code wrote) into {@code captured}. */
    private static BlobClient stubUploadCapturingBlob(BlobContainerClient blobContainerClient, String key,
                                                       AtomicReference<byte[]> captured) {
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(key)).thenReturn(blobClient);
        doAnswer(invocation -> {
            String source = invocation.getArgument(0);
            captured.set(Files.readAllBytes(Path.of(source)));
            return null;
        }).when(blobClient).uploadFromFile(anyString(), eq(true));
        return blobClient;
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-001 — local-storage processor, happy path
    // ----------------------------------------------------------------------------------------

    /**
     * KNOWN SPEC DEFECT (verified against real execution, not a migration-introduced production
     * bug): {@code test-cases.md} previously declared the expected thumbnail as
     * {@code max(width,height)=600, min(width,height)=400} for the 300x200 {@code sample.jpg}
     * fixture. Both the pre-migration baseline ({@code git show
     * 62d8ff6:.../AbstractFileProcessingService.java}) and the current migrated code contain the
     * identical "don't scale up images already smaller than the target bound" guard in
     * {@code progressiveScaling}, so a 300x200 source (which is already smaller than the computed
     * 600x400 target box) is never upscaled and the thumbnail stays 300x200 — exactly the same
     * no-upscale rule TC-WKR-003 (for {@code tiny.jpg}) correctly documents. This was a
     * baseline-authoring defect in the frozen spec (present since Phase 1, unrelated to this
     * migration); {@code test-cases.md}'s TC-WKR-001 expected dimensions have been re-frozen to
     * {@code 300x200} (task 008 follow-up remediation) and the assertions below now match that
     * re-frozen spec.
     */
    @Test
    void tcWkr001_processImageLocalHappyPath() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "sample.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "local",
                  "size": 2135
                }
                """);
        byte[] originalBytes = readFixture("inputs/sample.jpg");

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        BlobClient originalBlob = stubDownloadableBlob(blobContainerClient, "sample.jpg", originalBytes);
        AtomicReference<byte[]> uploadedThumbnail = new AtomicReference<>();
        BlobClient thumbnailBlob = stubUploadCapturingBlob(
                blobContainerClient, "sample_thumbnail.jpg", uploadedThumbnail);

        BlobFileProcessingService service = new BlobFileProcessingService(blobContainerClient);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        // Expected Response: acknowledged after successful processing.
        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();
        verify(context, never()).abandon();

        // Resource Verification: 300x200 thumbnail (no upscale; source already at/below the 600px bound).
        assertNotNull(uploadedThumbnail.get(), "thumbnail must have been uploaded");
        BufferedImage thumbnail = ImageIO.read(new ByteArrayInputStream(uploadedThumbnail.get()));
        assertNotNull(thumbnail, "uploaded thumbnail bytes must be a readable JPEG image");
        assertEquals(300, thumbnail.getWidth());
        assertEquals(200, thumbnail.getHeight());
        ArgumentCaptor<BlobHttpHeaders> headers = ArgumentCaptor.forClass(BlobHttpHeaders.class);
        verify(thumbnailBlob).setHttpHeaders(headers.capture());
        assertEquals("image/jpeg", headers.getValue().getContentType());

        // Negative Verification: no DB row (local processor has no repository dependency at all -
        // the class has no ImageMetadataRepository field/constructor argument, so there is
        // structurally no call site that could create one); original file unchanged.
        verify(originalBlob, never()).uploadFromFile(anyString(), any(Boolean.class));
        assertArrayEquals(originalBytes, readFixture("inputs/sample.jpg"),
                "the original fixture bytes must remain byte-identical (never mutated by the test or the service)");
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-002 — object-storage processor, happy path
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr002_processImageObjectStorageHappyPath() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "11111111-1111-4111-8111-111111111111-sample.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "s3",
                  "size": 2135
                }
                """);
        byte[] originalBytes = readFixture("inputs/sample.jpg");
        List<ImageMetadata> seeded = readSeedMetadata();
        ImageMetadata targetRow = seeded.stream()
                .filter(m -> "11111111-1111-4111-8111-111111111111-sample.jpg".equals(m.getS3Key()))
                .findFirst().orElseThrow();
        ImageMetadata unrelatedRow1 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-sample-portrait.png")).findFirst().orElseThrow();
        ImageMetadata unrelatedRow2 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-tiny.jpg")).findFirst().orElseThrow();

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubDownloadableBlob(blobContainerClient,
                "11111111-1111-4111-8111-111111111111-sample.jpg", originalBytes);
        AtomicReference<byte[]> uploadedThumbnail = new AtomicReference<>();
        BlobClient thumbnailBlob = stubUploadCapturingBlob(blobContainerClient,
                "11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg", uploadedThumbnail);
        ImageMetadataRepository imageMetadataRepository = mock(ImageMetadataRepository.class);
        when(imageMetadataRepository.findAll()).thenReturn(seeded);

        AzureBlobFileProcessingService service =
                new AzureBlobFileProcessingService(blobContainerClient, imageMetadataRepository);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        // Expected Response: acknowledged after successful processing.
        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();

        // Resource Verification: 300x200 thumbnail (no upscale; source already at/below the 600px bound).
        assertNotNull(uploadedThumbnail.get(),
                "thumbnail must have been uploaded (storageType \"s3\" is accepted as a legacy "
                        + "alias for \"azure-blob\")");
        BufferedImage thumbnail = ImageIO.read(new ByteArrayInputStream(uploadedThumbnail.get()));
        assertNotNull(thumbnail);
        assertEquals(300, thumbnail.getWidth());
        assertEquals(200, thumbnail.getHeight());
        ArgumentCaptor<BlobHttpHeaders> headers = ArgumentCaptor.forClass(BlobHttpHeaders.class);
        verify(thumbnailBlob).setHttpHeaders(headers.capture());
        assertEquals("image/jpeg", headers.getValue().getContentType());

        assertEquals("11111111-1111-4111-8111-111111111111-sample_thumbnail.jpg", targetRow.getThumbnailKey());
        assertNotNull(targetRow.getThumbnailUrl());

        // Negative Verification: only one row updated, others untouched.
        ArgumentCaptor<ImageMetadata> saved = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).save(saved.capture());
        assertEquals(targetRow.getId(), saved.getValue().getId());
        assertNull(unrelatedRow1.getThumbnailKey());
        assertNull(unrelatedRow2.getThumbnailKey());
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-003 — local-storage processor, boundary (sub-600px source not upscaled)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr003_processImageLocalTinyNotUpscaled() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "tiny.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "local",
                  "size": 633
                }
                """);
        byte[] originalBytes = readFixture("inputs/tiny.jpg");

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubDownloadableBlob(blobContainerClient, "tiny.jpg", originalBytes);
        AtomicReference<byte[]> uploadedThumbnail = new AtomicReference<>();
        stubUploadCapturingBlob(blobContainerClient, "tiny_thumbnail.jpg", uploadedThumbnail);

        BlobFileProcessingService service = new BlobFileProcessingService(blobContainerClient);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();

        assertNotNull(uploadedThumbnail.get());
        BufferedImage thumbnail = ImageIO.read(new ByteArrayInputStream(uploadedThumbnail.get()));
        assertNotNull(thumbnail);
        assertEquals(1, thumbnail.getWidth(), "1x1 source must not be upscaled to the 600px bound");
        assertEquals(1, thumbnail.getHeight(), "1x1 source must not be upscaled to the 600px bound");
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-004 — object-storage processor, boundary (portrait PNG with alpha)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr004_processImageObjectStoragePortraitAlphaPreserved() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "22222222-2222-4222-8222-222222222222-sample-portrait.png",
                  "contentType": "image/png",
                  "storageType": "s3",
                  "size": 1076
                }
                """);
        byte[] originalBytes = readFixture("inputs/sample-portrait.png");
        List<ImageMetadata> seeded = readSeedMetadata();
        ImageMetadata targetRow = seeded.stream()
                .filter(m -> "22222222-2222-4222-8222-222222222222-sample-portrait.png".equals(m.getS3Key()))
                .findFirst().orElseThrow();
        ImageMetadata unrelatedRow1 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-sample.jpg")).findFirst().orElseThrow();
        ImageMetadata unrelatedRow2 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-tiny.jpg")).findFirst().orElseThrow();

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubDownloadableBlob(blobContainerClient,
                "22222222-2222-4222-8222-222222222222-sample-portrait.png", originalBytes);
        AtomicReference<byte[]> uploadedThumbnail = new AtomicReference<>();
        stubUploadCapturingBlob(blobContainerClient,
                "22222222-2222-4222-8222-222222222222-sample-portrait_thumbnail.png", uploadedThumbnail);
        ImageMetadataRepository imageMetadataRepository = mock(ImageMetadataRepository.class);
        when(imageMetadataRepository.findAll()).thenReturn(seeded);

        AzureBlobFileProcessingService service =
                new AzureBlobFileProcessingService(blobContainerClient, imageMetadataRepository);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();

        assertNotNull(uploadedThumbnail.get(), "thumbnail must have been uploaded");
        BufferedImage thumbnail = ImageIO.read(new ByteArrayInputStream(uploadedThumbnail.get()));
        assertNotNull(thumbnail);
        assertEquals(150, thumbnail.getWidth());
        assertEquals(300, thumbnail.getHeight());
        assertTrue(thumbnail.getColorModel().hasAlpha(), "alpha channel must be preserved");

        assertEquals("22222222-2222-4222-8222-222222222222-sample-portrait_thumbnail.png",
                targetRow.getThumbnailKey());
        assertNotNull(targetRow.getThumbnailUrl());
        assertNull(unrelatedRow1.getThumbnailKey());
        assertNull(unrelatedRow2.getThumbnailKey());
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-005 — local-storage processor, special-input (other storage type skipped)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr005_processImageLocalSkipsOtherStorageType() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "11111111-1111-4111-8111-111111111111-sample.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "s3",
                  "size": 2135
                }
                """);

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        BlobFileProcessingService service = new BlobFileProcessingService(blobContainerClient);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        // Expected Response: acknowledged without processing (mismatch treated as success).
        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();

        // Negative Verification: no file access of any kind, no thumbnail creation attempt.
        verify(blobContainerClient, never()).getBlobClient(anyString());
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-006 — object-storage processor, special-input (Unicode key with embedded space)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr006_processImageObjectStorageUnicodeKey() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "테스트 이미지.png",
                  "contentType": "image/png",
                  "storageType": "s3",
                  "size": 1076
                }
                """);
        byte[] originalBytes = readFixture("inputs/sample-portrait.png");

        ImageMetadata row = new ImageMetadata();
        row.setId("unicode-row-1");
        row.setFilename("테스트 이미지.png");
        row.setContentType("image/png");
        row.setSize(1076L);
        row.setS3Key("테스트 이미지.png");
        List<ImageMetadata> seeded = List.of(row);

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubDownloadableBlob(blobContainerClient, "테스트 이미지.png", originalBytes);
        AtomicReference<byte[]> uploadedThumbnail = new AtomicReference<>();
        stubUploadCapturingBlob(blobContainerClient, "테스트 이미지_thumbnail.png", uploadedThumbnail);
        ImageMetadataRepository imageMetadataRepository = mock(ImageMetadataRepository.class);
        when(imageMetadataRepository.findAll()).thenReturn(seeded);

        AzureBlobFileProcessingService service =
                new AzureBlobFileProcessingService(blobContainerClient, imageMetadataRepository);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        verify(context, times(1)).complete();
        verify(context, never()).deadLetter();

        assertNotNull(uploadedThumbnail.get(), "thumbnail must have been uploaded");
        BufferedImage thumbnail = ImageIO.read(new ByteArrayInputStream(uploadedThumbnail.get()));
        assertNotNull(thumbnail);
        assertEquals(150, thumbnail.getWidth());
        assertEquals(300, thumbnail.getHeight());

        assertEquals("테스트 이미지_thumbnail.png", row.getThumbnailKey());
        assertNotNull(row.getThumbnailUrl());

        // Negative Verification: no additional row created.
        ArgumentCaptor<ImageMetadata> saved = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).save(saved.capture());
        assertEquals("unicode-row-1", saved.getValue().getId());
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-007 — local-storage processor, failure (source file missing)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr007_processImageLocalSourceMissingDeadLetters() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "missing.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "local",
                  "size": 2135
                }
                """);

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubMissingBlob(blobContainerClient, "missing.jpg");

        BlobFileProcessingService service = new BlobFileProcessingService(blobContainerClient);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        // Resource Verification: rejected without requeue (dead-lettered), not acknowledged.
        verify(context, times(1)).deadLetter();
        verify(context, never()).complete();
        verify(context, never()).abandon();

        // Negative Verification: no thumbnail upload was ever attempted.
        verify(blobContainerClient, never()).getBlobClient("missing_thumbnail.jpg");
    }

    // ----------------------------------------------------------------------------------------
    // TC-WKR-008 — object-storage processor, failure (corrupt source image)
    // ----------------------------------------------------------------------------------------

    @Test
    void tcWkr008_processImageObjectStorageCorruptSourceDeadLetters() throws Exception {
        ImageProcessingMessage message = trigger("""
                {
                  "key": "33333333-3333-4333-8333-333333333333-tiny.jpg",
                  "contentType": "image/jpeg",
                  "storageType": "s3",
                  "size": 74
                }
                """);
        byte[] corruptBytes = readFixture("inputs/corrupt.jpg");
        List<ImageMetadata> seeded = readSeedMetadata();
        ImageMetadata targetRow = seeded.stream()
                .filter(m -> "33333333-3333-4333-8333-333333333333-tiny.jpg".equals(m.getS3Key()))
                .findFirst().orElseThrow();
        ImageMetadata unrelatedRow1 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-sample.jpg")).findFirst().orElseThrow();
        ImageMetadata unrelatedRow2 = seeded.stream()
                .filter(m -> m.getS3Key().endsWith("-sample-portrait.png")).findFirst().orElseThrow();

        BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);
        stubDownloadableBlob(blobContainerClient,
                "33333333-3333-4333-8333-333333333333-tiny.jpg", corruptBytes);
        ImageMetadataRepository imageMetadataRepository = mock(ImageMetadataRepository.class);
        when(imageMetadataRepository.findAll()).thenReturn(seeded);

        AzureBlobFileProcessingService service =
                new AzureBlobFileProcessingService(blobContainerClient, imageMetadataRepository);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        // Resource Verification: rejected without requeue (dead-lettered), not acknowledged.
        verify(context, times(1)).deadLetter();
        verify(context, never()).complete();

        // Negative Verification: no thumbnail object created, metadata row left untouched.
        verify(blobContainerClient, never())
                .getBlobClient("33333333-3333-4333-8333-333333333333-tiny_thumbnail.jpg");
        verify(imageMetadataRepository, never()).save(any());
        assertFalse(seeded.stream().anyMatch(m -> m.getThumbnailKey() != null));
        assertNull(targetRow.getThumbnailKey());
        assertNull(targetRow.getThumbnailUrl());
        assertNull(unrelatedRow1.getThumbnailKey());
        assertNull(unrelatedRow2.getThumbnailKey());
    }
}
