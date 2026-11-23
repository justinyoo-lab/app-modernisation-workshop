package com.microsoft.migration.assets.worker.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the dev-profile {@link BlobFileProcessingService}. Thumbnail-generation tests
 * exercise real image processing (no I/O against storage); the download/upload tests mock
 * {@link BlobContainerClient}/{@link BlobClient} so no real Azure Blob Storage account is
 * contacted.
 */
@ExtendWith(MockitoExtension.class)
class BlobFileProcessingServiceTest {

    @TempDir
    Path tempDir;

    @Mock
    private BlobContainerClient blobContainerClient;

    @Mock
    private BlobClient blobClient;

    private BlobFileProcessingService service;

    @BeforeEach
    void setUp() {
        service = new BlobFileProcessingService(blobContainerClient);
    }

    @Test
    void generatesThumbnailFromOpaquePng() throws Exception {
        BufferedImage image = new BufferedImage(100, 100, BufferedImage.TYPE_3BYTE_BGR);
        image.setRGB(50, 50, 0xffff0000);
        Path original = tempDir.resolve("opaque.png");
        Path thumbnail = tempDir.resolve("opaque-thumbnail.png");
        assertTrue(ImageIO.write(image, "png", original.toFile()));

        service.generateThumbnail(original, thumbnail);

        BufferedImage result = ImageIO.read(thumbnail.toFile());
        assertEquals(100, result.getWidth());
        assertEquals(100, result.getHeight());
        assertEquals(0xffff0000, result.getRGB(50, 50));
    }

    @Test
    void generatesThumbnailFromTransparentPng() throws Exception {
        BufferedImage image = new BufferedImage(100, 100, BufferedImage.TYPE_4BYTE_ABGR);
        image.setRGB(50, 50, 0x80ff0000);
        Path original = tempDir.resolve("original.png");
        Path thumbnail = tempDir.resolve("thumbnail.png");
        assertTrue(ImageIO.write(image, "png", original.toFile()));

        service.generateThumbnail(original, thumbnail);

        BufferedImage result = ImageIO.read(thumbnail.toFile());
        assertEquals(100, result.getWidth());
        assertEquals(100, result.getHeight());
        assertTrue(result.getColorModel().hasAlpha());
    }

    @Test
    void downloadOriginalDownloadsExistingBlobToDestination() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        Path destination = tempDir.resolve("downloaded.jpg");

        service.downloadOriginal("photo.jpg", destination);

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
    void uploadThumbnailUploadsFileAndSetsContentType() throws Exception {
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(blobClient);
        Path source = tempDir.resolve("thumb.jpg");
        Files.write(source, "thumbnail-bytes".getBytes());

        service.uploadThumbnail(source, "photo_thumbnail.jpg", "image/jpeg");

        verify(blobClient).uploadFromFile(source.toString(), true);
        verify(blobClient).setHttpHeaders(any());
    }

    @Test
    void uploadThumbnailRejectsPathTraversalKeyWithoutTouchingBlobStorage() throws IOException {
        Path source = tempDir.resolve("thumb.jpg");
        Files.write(source, "bytes".getBytes());

        assertThrows(IOException.class, () -> service.uploadThumbnail(source, "../../escape.jpg", "image/jpeg"));

        verify(blobContainerClient, never()).getBlobClient(any());
    }

    @Test
    void getStorageTypeIsLocalForRoutingCompatibility() {
        assertEquals("local", service.getStorageType());
    }

    @Test
    void generateUrlReturnsAppRelativePathNoSasNoPublicUrl() {
        assertEquals("/storage/photo_thumbnail.jpg", service.generateUrl("photo_thumbnail.jpg"));
    }
}
