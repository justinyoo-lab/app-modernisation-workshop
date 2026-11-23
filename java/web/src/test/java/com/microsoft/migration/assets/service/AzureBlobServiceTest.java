package com.microsoft.migration.assets.service;

import com.azure.core.http.rest.PagedIterable;
import com.azure.core.util.BinaryData;
import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobItemProperties;
import com.azure.storage.blob.models.BlobStorageException;
import com.microsoft.migration.assets.model.ImageMetadata;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.S3StorageItem;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
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
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.List;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for the non-dev/object-storage-profile {@link AzureBlobService}, which replaces the
 * previous AWS S3-backed implementation. All Azure Blob Storage, Service Bus, and
 * {@link ImageMetadataRepository} interactions are mocked: no real storage account, Service Bus
 * namespace, or database is contacted.
 */
@ExtendWith(MockitoExtension.class)
class AzureBlobServiceTest {

    @Mock
    private BlobContainerClient blobContainerClient;

    @Mock
    private BlobClient blobClient;

    @Mock
    private BlobClient thumbnailBlobClient;

    @Mock
    private ServiceBusTemplate serviceBusTemplate;

    @Mock
    private ImageMetadataRepository imageMetadataRepository;

    private AzureBlobService azureBlobService;

    @BeforeEach
    void setUp() {
        azureBlobService = new AzureBlobService(blobContainerClient, serviceBusTemplate, imageMetadataRepository);
    }

    @Test
    void uploadStoresBlobPublishesMessageAndCreatesMetadataRow() throws Exception {
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient);
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        azureBlobService.uploadObject(file);

        verify(blobClient).upload(any(InputStream.class), eq((long) "sample-bytes".getBytes().length), eq(true));
        verify(blobClient).setHttpHeaders(any());

        ArgumentCaptor<Message<ImageProcessingMessage>> captor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), captor.capture());
        ImageProcessingMessage payload = captor.getValue().getPayload();
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals("azure-blob", payload.getStorageType());
        assertTrue(payload.getKey().endsWith("-photo.jpg"));

        ArgumentCaptor<ImageMetadata> metadataCaptor = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).save(metadataCaptor.capture());
        ImageMetadata savedMetadata = metadataCaptor.getValue();
        assertEquals("photo.jpg", savedMetadata.getFilename());
        assertEquals("image/jpeg", savedMetadata.getContentType());
        assertEquals((long) "sample-bytes".getBytes().length, savedMetadata.getSize());
        assertTrue(savedMetadata.getS3Key().endsWith("-photo.jpg"));
        assertEquals(savedMetadata.getS3Key(), payload.getKey());
    }

    @Test
    void duplicateUploadsEachPublishAnIndependentMessageAndCreateDistinctMetadataRows() throws Exception {
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient);
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        azureBlobService.uploadObject(file);
        azureBlobService.uploadObject(file);

        verify(serviceBusTemplate, times(2)).send(eq(IMAGE_PROCESSING_QUEUE), any());
        verify(imageMetadataRepository, times(2)).save(any());
    }

    @Test
    void uploadRejectsEmptyFileWithoutTouchingBlobStorageOrQueueOrDatabase() {
        MockMultipartFile emptyFile = new MockMultipartFile("file", "photo.jpg", "image/jpeg", new byte[0]);

        assertThrows(IOException.class, () -> azureBlobService.uploadObject(emptyFile));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
        verify(imageMetadataRepository, never()).save(any());
    }

    @Test
    void uploadRejectsPathTraversalFilenameWithoutTouchingBlobStorageOrQueueOrDatabase() {
        MockMultipartFile file = new MockMultipartFile("file", "../../secret.jpg", "image/jpeg", "bytes".getBytes());

        assertThrows(IOException.class, () -> azureBlobService.uploadObject(file));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
        verify(imageMetadataRepository, never()).save(any());
    }

    @Test
    void uploadWrapsBlobStorageExceptionAsIOException() {
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient);
        doThrow(mock(BlobStorageException.class)).when(blobClient)
                .upload(any(InputStream.class), any(Long.class), eq(true));
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "bytes".getBytes());

        assertThrows(IOException.class, () -> azureBlobService.uploadObject(file));

        verify(serviceBusTemplate, never()).send(any(), any());
        verify(imageMetadataRepository, never()).save(any());
    }

    @Test
    void getObjectReturnsContentForExistingBlob() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        when(blobClient.downloadContent()).thenReturn(BinaryData.fromString("hello"));

        try (InputStream result = azureBlobService.getObject("photo.jpg")) {
            assertEquals("hello", new String(result.readAllBytes()));
        }
    }

    @Test
    void getObjectThrowsFileNotFoundForMissingBlob() {
        when(blobContainerClient.getBlobClient("missing.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);

        assertThrows(FileNotFoundException.class, () -> azureBlobService.getObject("missing.jpg"));
    }

    @Test
    void getObjectRejectsPathTraversalKeyWithoutTouchingBlobStorage() {
        assertThrows(IOException.class, () -> azureBlobService.getObject("../../secret.jpg"));

        verify(blobContainerClient, never()).getBlobClient(any());
    }

    @Test
    void deleteObjectDeletesOriginalAndThumbnailAndRemovesMetadataRow() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId("meta-1");
        metadata.setS3Key("photo.jpg");
        when(imageMetadataRepository.findAll()).thenReturn(List.of(metadata));

        azureBlobService.deleteObject("photo.jpg");

        verify(blobClient).deleteIfExists();
        verify(thumbnailBlobClient).deleteIfExists();
        verify(imageMetadataRepository).delete(metadata);
    }

    @Test
    void deleteObjectLeavesUnrelatedMetadataRowsUntouched() throws Exception {
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient, thumbnailBlobClient);
        ImageMetadata target = new ImageMetadata();
        target.setId("meta-1");
        target.setS3Key("photo.jpg");
        ImageMetadata other = new ImageMetadata();
        other.setId("meta-2");
        other.setS3Key("other.jpg");
        when(imageMetadataRepository.findAll()).thenReturn(List.of(target, other));

        azureBlobService.deleteObject("photo.jpg");

        verify(imageMetadataRepository).delete(target);
        verify(imageMetadataRepository, never()).delete(other);
    }

    @Test
    void deleteObjectToleratesThumbnailDeletionFailure() throws Exception {
        when(blobContainerClient.getBlobClient("photo.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        when(imageMetadataRepository.findAll()).thenReturn(List.of());
        doThrow(new RuntimeException("boom")).when(thumbnailBlobClient).deleteIfExists();

        // Should not propagate: deleting the thumbnail is best-effort, matching the previous
        // AWS S3-backed implementation's behavior.
        azureBlobService.deleteObject("photo.jpg");

        verify(blobClient).deleteIfExists();
    }

    @Test
    void deleteObjectRejectsPathTraversalKeyWithoutTouchingBlobStorageOrDatabase() {
        assertThrows(IOException.class, () -> azureBlobService.deleteObject("../../secret.jpg"));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(imageMetadataRepository, never()).findAll();
    }

    @Test
    @SuppressWarnings("unchecked")
    void listObjectsResolvesUploadedAtFromMetadataWhenPresent() {
        BlobItem blobItem = mock(BlobItem.class);
        BlobItemProperties properties = mock(BlobItemProperties.class);
        when(blobItem.getName()).thenReturn("photo.jpg");
        when(blobItem.getProperties()).thenReturn(properties);
        when(properties.getLastModified()).thenReturn(OffsetDateTime.now().minusDays(1));
        when(properties.getContentLength()).thenReturn(1234L);

        ImageMetadata metadata = new ImageMetadata();
        metadata.setS3Key("photo.jpg");
        metadata.setUploadedAt(LocalDateTime.now());
        when(imageMetadataRepository.findAll()).thenReturn(List.of(metadata));

        PagedIterable<BlobItem> pagedIterable = mock(PagedIterable.class);
        when(pagedIterable.stream()).thenReturn(List.of(blobItem).stream());
        when(blobContainerClient.listBlobs()).thenReturn(pagedIterable);

        List<S3StorageItem> items = azureBlobService.listObjects();

        assertEquals(1, items.size());
        assertEquals("photo.jpg", items.get(0).getKey());
        assertEquals(1234L, items.get(0).getSize());
        assertEquals("/storage/view/photo.jpg", items.get(0).getUrl());
    }

    @Test
    @SuppressWarnings("unchecked")
    void listObjectsFallsBackToLastModifiedWhenNoMetadataRowMatches() {
        BlobItem blobItem = mock(BlobItem.class);
        BlobItemProperties properties = mock(BlobItemProperties.class);
        OffsetDateTime lastModified = OffsetDateTime.now();
        when(blobItem.getName()).thenReturn("photo.jpg");
        when(blobItem.getProperties()).thenReturn(properties);
        when(properties.getLastModified()).thenReturn(lastModified);
        when(properties.getContentLength()).thenReturn(1234L);
        when(imageMetadataRepository.findAll()).thenReturn(List.of());

        PagedIterable<BlobItem> pagedIterable = mock(PagedIterable.class);
        when(pagedIterable.stream()).thenReturn(List.of(blobItem).stream());
        when(blobContainerClient.listBlobs()).thenReturn(pagedIterable);

        List<S3StorageItem> items = azureBlobService.listObjects();

        assertEquals(1, items.size());
        assertEquals(lastModified.toInstant(), items.get(0).getUploadedAt());
    }

    @Test
    void listObjectsReturnsEmptyListWhenBlobStorageExceptionIsThrown() {
        when(blobContainerClient.listBlobs()).thenThrow(mock(BlobStorageException.class));

        List<S3StorageItem> items = azureBlobService.listObjects();

        assertTrue(items.isEmpty());
    }

    @Test
    void getStorageTypeIsAzureBlobForRoutingCompatibility() {
        assertEquals("azure-blob", azureBlobService.getStorageType());
    }
}
