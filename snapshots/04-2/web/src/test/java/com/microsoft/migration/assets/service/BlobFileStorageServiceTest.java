package com.microsoft.migration.assets.service;

import com.azure.core.http.rest.PagedIterable;
import com.azure.core.util.BinaryData;
import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobItemProperties;
import com.microsoft.migration.assets.config.BackupQueue;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.S3StorageItem;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.Message;
import org.springframework.mock.web.MockMultipartFile;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the dev-profile {@link BlobFileStorageService}. All Azure Blob Storage and
 * Service Bus interactions are mocked: no real storage account or Service Bus namespace is
 * contacted.
 */
@ExtendWith(MockitoExtension.class)
class BlobFileStorageServiceTest {

    @Mock
    private ServiceBusTemplate serviceBusTemplate;

    @Mock
    private BlobContainerClient blobContainerClient;

    @Mock
    private BlobClient blobClient;

    @Mock
    private BlobClient thumbnailBlobClient;

    private BlobFileStorageService storageService;

    @BeforeEach
    void setUp() {
        storageService = new BlobFileStorageService(serviceBusTemplate, blobContainerClient, Optional.empty());
    }

    @Test
    void uploadPublishesMessageToImageProcessingQueueAndUploadsBlob() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        storageService.uploadObject(file);

        verify(blobClient).upload(any(InputStream.class), eq((long) "sample-bytes".getBytes().length), eq(true));

        ArgumentCaptor<Message<ImageProcessingMessage>> captor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), captor.capture());
        ImageProcessingMessage payload = captor.getValue().getPayload();
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals("local", payload.getStorageType());
        assertEquals("photo.jpg", payload.getKey());
    }

    @Test
    void duplicateUploadsEachPublishAnIndependentMessage() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        storageService.uploadObject(file);
        storageService.uploadObject(file);

        verify(serviceBusTemplate, times(2)).send(eq(IMAGE_PROCESSING_QUEUE), any());
    }

    @Test
    void backupProfilePublishesCopyToSeparateQueue() throws Exception {
        storageService = new BlobFileStorageService(serviceBusTemplate, blobContainerClient,
                Optional.of(new BackupQueue("backup-monitoring")));
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        storageService.uploadObject(new MockMultipartFile("file", "photo.jpg", "image/jpeg", "bytes".getBytes()));
        verify(serviceBusTemplate).send(eq(IMAGE_PROCESSING_QUEUE), any());
        verify(serviceBusTemplate).send(eq("backup-monitoring"), any());
    }

    @Test
    void backupFailureIsReportedAfterPrimaryPublish() {
        storageService = new BlobFileStorageService(serviceBusTemplate, blobContainerClient,
                Optional.of(new BackupQueue("backup-monitoring")));
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        lenient().doThrow(new IllegalStateException("unavailable"))
                .when(serviceBusTemplate).send(eq("backup-monitoring"), any());
        assertThrows(IOException.class, () -> storageService.uploadObject(
                new MockMultipartFile("file", "photo.jpg", "image/jpeg", "bytes".getBytes())));
        verify(serviceBusTemplate).send(eq(IMAGE_PROCESSING_QUEUE), any());
    }

    @Test
    void uploadRejectsPathTraversalFilenameWithoutTouchingBlobStorageOrQueue() {
        MockMultipartFile file = new MockMultipartFile("file", "../../secret.jpg", "image/jpeg", "bytes".getBytes());

        assertThrows(IOException.class, () -> storageService.uploadObject(file));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
    }

    @Test
    void uploadRejectsEmptyFile() {
        MockMultipartFile emptyFile = new MockMultipartFile("file", "photo.jpg", "image/jpeg", new byte[0]);

        assertThrows(IOException.class, () -> storageService.uploadObject(emptyFile));
    }

    @Test
    void getObjectReturnsContentForExistingBlob() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        when(blobClient.downloadContent()).thenReturn(BinaryData.fromString("hello"));

        try (InputStream result = storageService.getObject("photo.jpg")) {
            assertEquals("hello", new String(result.readAllBytes()));
        }
    }

    @Test
    void getObjectThrowsFileNotFoundForMissingBlob() {
        when(blobContainerClient.getBlobClient("missing.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);

        assertThrows(FileNotFoundException.class, () -> storageService.getObject("missing.jpg"));
    }

    @Test
    void getObjectRejectsPathTraversalKeyWithoutTouchingBlobStorage() {
        assertThrows(IOException.class, () -> storageService.getObject("../../secret.jpg"));

        verify(blobContainerClient, never()).getBlobClient(any());
    }

    @Test
    void deleteObjectDeletesOriginalAndThumbnailWhenBothExist() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        when(blobClient.exists()).thenReturn(true);
        when(thumbnailBlobClient.exists()).thenReturn(true);

        storageService.deleteObject("photo.jpg");

        verify(blobClient).delete();
        verify(thumbnailBlobClient).delete();
    }

    @Test
    void deleteObjectSkipsThumbnailWhenItDoesNotExist() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        when(blobClient.exists()).thenReturn(true);
        when(thumbnailBlobClient.exists()).thenReturn(false);

        storageService.deleteObject("photo.jpg");

        verify(blobClient).delete();
        verify(thumbnailBlobClient, never()).delete();
    }

    @Test
    void deleteObjectThrowsFileNotFoundForMissingBlob() {
        when(blobContainerClient.getBlobClient("missing.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);

        assertThrows(FileNotFoundException.class, () -> storageService.deleteObject("missing.jpg"));
        verify(blobClient, never()).delete();
    }

    @Test
    void deleteObjectToleratesThumbnailDeletionFailure() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        when(blobClient.exists()).thenReturn(true);
        when(thumbnailBlobClient.exists()).thenReturn(true);
        doThrow(new RuntimeException("boom")).when(thumbnailBlobClient).delete();

        // Should not propagate: deleting the thumbnail is best-effort, matching the original
        // local-filesystem implementation's behavior.
        storageService.deleteObject("photo.jpg");

        verify(blobClient).delete();
    }

    @Test
    @SuppressWarnings("unchecked")
    void listObjectsMapsBlobItemsToStorageItems() {
        BlobItem blobItem = mock(BlobItem.class);
        BlobItemProperties properties = mock(BlobItemProperties.class);
        when(blobItem.getName()).thenReturn("photo.jpg");
        when(blobItem.getProperties()).thenReturn(properties);
        when(properties.getLastModified()).thenReturn(OffsetDateTime.now());
        when(properties.getCreationTime()).thenReturn(OffsetDateTime.now());
        when(properties.getContentLength()).thenReturn(1234L);

        PagedIterable<BlobItem> pagedIterable = mock(PagedIterable.class);
        when(pagedIterable.stream()).thenReturn(List.of(blobItem).stream());
        when(blobContainerClient.listBlobs()).thenReturn(pagedIterable);

        List<S3StorageItem> items = storageService.listObjects();

        assertEquals(1, items.size());
        assertEquals("photo.jpg", items.get(0).getKey());
        assertEquals(1234L, items.get(0).getSize());
        assertEquals("/storage/view/photo.jpg", items.get(0).getUrl());
    }

    @Test
    void getStorageTypeIsLocalForRoutingCompatibility() {
        assertEquals("local", storageService.getStorageType());
    }
}
