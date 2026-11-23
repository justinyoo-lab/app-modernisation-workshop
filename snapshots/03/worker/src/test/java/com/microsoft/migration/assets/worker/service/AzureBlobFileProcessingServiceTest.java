package com.microsoft.migration.assets.worker.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.microsoft.migration.assets.worker.model.ImageMetadata;
import com.microsoft.migration.assets.worker.repository.ImageMetadataRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the non-dev/object-storage-profile {@link AzureBlobFileProcessingService}, which
 * replaces the previous AWS S3-backed implementation. All Azure Blob Storage and
 * {@link ImageMetadataRepository} interactions are mocked: no real Azure Blob Storage account or
 * database is contacted.
 */
@ExtendWith(MockitoExtension.class)
class AzureBlobFileProcessingServiceTest {

    @TempDir
    Path tempDir;

    @Mock
    private BlobContainerClient blobContainerClient;

    @Mock
    private BlobClient blobClient;

    @Mock
    private ImageMetadataRepository imageMetadataRepository;

    private AzureBlobFileProcessingService service;

    @BeforeEach
    void setUp() {
        service = new AzureBlobFileProcessingService(blobContainerClient, imageMetadataRepository);
    }

    @Test
    void getStorageTypeIsAzureBlobForRoutingCompatibility() {
        assertEquals("azure-blob", service.getStorageType());
    }

    @Test
    void downloadOriginalDownloadsExistingBlobToDestination() throws Exception {
        when(blobContainerClient.getBlobClient("test-image.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        Path destination = tempDir.resolve("downloaded.jpg");

        service.downloadOriginal("test-image.jpg", destination);

        verify(blobClient).downloadToFile(destination.toString(), true);
    }

    @Test
    void downloadOriginalThrowsFileNotFoundForMissingBlob() {
        when(blobContainerClient.getBlobClient("missing.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);
        Path destination = tempDir.resolve("downloaded.jpg");

        assertThrows(FileNotFoundException.class, () -> service.downloadOriginal("missing.jpg", destination));
        verify(blobClient, never()).downloadToFile(any(), any(Boolean.class));
    }

    @Test
    void downloadOriginalRejectsPathTraversalKeyWithoutTouchingBlobStorage() {
        Path destination = tempDir.resolve("downloaded.jpg");

        assertThrows(IOException.class, () -> service.downloadOriginal("../../secret.jpg", destination));

        verify(blobContainerClient, never()).getBlobClient(any());
    }

    @Test
    void uploadThumbnailUploadsFileSetsContentTypeAndUpdatesMetadata() throws Exception {
        when(blobContainerClient.getBlobClient("test-image_thumbnail.jpg")).thenReturn(blobClient);
        Path source = tempDir.resolve("thumb.jpg");
        Files.write(source, "thumbnail-bytes".getBytes());

        ImageMetadata metadata = new ImageMetadata();
        metadata.setId("meta-1");
        metadata.setS3Key("test-image.jpg");
        when(imageMetadataRepository.findAll()).thenReturn(List.of(metadata));

        service.uploadThumbnail(source, "test-image_thumbnail.jpg", "image/jpeg");

        verify(blobClient).uploadFromFile(source.toString(), true);
        verify(blobClient).setHttpHeaders(any());

        ArgumentCaptor<ImageMetadata> captor = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository).save(captor.capture());
        assertEquals("test-image_thumbnail.jpg", captor.getValue().getThumbnailKey());
        assertEquals("/storage/test-image_thumbnail.jpg", captor.getValue().getThumbnailUrl());
    }

    @Test
    void uploadThumbnailLeavesUnrelatedMetadataRowsUntouchedWhenNoMatchFound() throws Exception {
        when(blobContainerClient.getBlobClient("test-image_thumbnail.jpg")).thenReturn(blobClient);
        Path source = tempDir.resolve("thumb.jpg");
        Files.write(source, "thumbnail-bytes".getBytes());
        when(imageMetadataRepository.findAll()).thenReturn(List.of());

        service.uploadThumbnail(source, "test-image_thumbnail.jpg", "image/jpeg");

        verify(imageMetadataRepository, never()).save(any());
    }

    @Test
    void uploadThumbnailRejectsPathTraversalKeyWithoutTouchingBlobStorageOrDatabase() throws IOException {
        Path source = tempDir.resolve("thumb.jpg");
        Files.write(source, "bytes".getBytes());

        assertThrows(IOException.class, () -> service.uploadThumbnail(source, "../../escape.jpg", "image/jpeg"));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(imageMetadataRepository, never()).findAll();
    }

    @Test
    void generateUrlReturnsAppRelativePathNoSasNoPublicUrl() {
        assertEquals("/storage/test-image_thumbnail.jpg", service.generateUrl("test-image_thumbnail.jpg"));
    }

    @Test
    void extractOriginalKeyStripsThumbnailSuffix() {
        String result = (String) ReflectionTestUtils.invokeMethod(
                service,
                "extractOriginalKey",
                "image_thumbnail.jpg");

        assertEquals("image.jpg", result);
    }
}
