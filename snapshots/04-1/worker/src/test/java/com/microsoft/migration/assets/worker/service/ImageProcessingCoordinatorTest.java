package com.microsoft.migration.assets.worker.service;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.microsoft.migration.assets.worker.model.ImageMetadata;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import com.microsoft.migration.assets.worker.repository.ImageMetadataRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@DataJpaTest
@Import(ImageProcessingCoordinator.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class ImageProcessingCoordinatorTest {
    @Autowired private ImageMetadataRepository repository;
    @Autowired private ImageProcessingCoordinator coordinator;
    @Autowired private PlatformTransactionManager transactionManager;
    @MockitoBean private BlobContainerClient container;

    @BeforeEach
    void clearRows() {
        repository.deleteAll();
    }

    private void seedMetadata() {
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId("row");
        metadata.setFilename("photo.jpg");
        metadata.setS3Key("photo.jpg");
        repository.saveAndFlush(metadata);
    }

    @Test
    void concurrentDuplicateDeliveriesKeepOneThumbnailAndDoNotRewriteMetadata() throws Exception {
        seedMetadata();
        BlobClient original = mock(BlobClient.class);
        BlobClient thumbnail = mock(BlobClient.class);
        when(container.getBlobClient("photo.jpg")).thenReturn(original);
        when(container.getBlobClient("photo_thumbnail.jpg")).thenReturn(thumbnail);
        when(original.exists()).thenReturn(true);
        ByteArrayOutputStream image = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(20, 20, BufferedImage.TYPE_INT_RGB), "jpg", image);
        doAnswer(call -> {
            Files.write(Path.of((String) call.getArgument(0)), image.toByteArray());
            return null;
        }).when(original).downloadToFile(any(), eq(true));
        AtomicReference<byte[]> stored = new AtomicReference<>();
        AtomicInteger uploads = new AtomicInteger();
        CountDownLatch uploadStarted = new CountDownLatch(1);
        CountDownLatch releaseUpload = new CountDownLatch(1);
        doAnswer(call -> {
            uploads.incrementAndGet();
            stored.set(Files.readAllBytes(Path.of((String) call.getArgument(0))));
            uploadStarted.countDown();
            assertTrue(releaseUpload.await(10, TimeUnit.SECONDS));
            return null;
        }).when(thumbnail).uploadFromFile(any(), eq(true));
        when(thumbnail.exists()).thenAnswer(call -> stored.get() != null);

        var service = new AzureBlobFileProcessingService(container, repository, coordinator);
        var message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "azure-blob", 10);
        var firstContext = mock(ServiceBusReceivedMessageContext.class);
        var secondContext = mock(ServiceBusReceivedMessageContext.class);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> service.processImage(message, firstContext));
            assertTrue(uploadStarted.await(10, TimeUnit.SECONDS));
            var second = executor.submit(() -> service.processImage(message, secondContext));
            releaseUpload.countDown();
            first.get(10, TimeUnit.SECONDS);
            second.get(10, TimeUnit.SECONDS);
        } finally {
            releaseUpload.countDown();
        }

        verify(firstContext).complete();
        verify(secondContext).complete();
        assertEquals(1, uploads.get());
        byte[] firstThumbnail = stored.get();
        assertNotNull(firstThumbnail);
        ImageMetadata saved = repository.findById("row").orElseThrow();
        var modified = saved.getLastModified();
        service.processImage(message, mock(ServiceBusReceivedMessageContext.class));
        assertEquals(modified, repository.findById("row").orElseThrow().getLastModified());
        assertEquals(1, uploads.get());
        assertArrayEquals(firstThumbnail, stored.get());
    }

    @Test
    void deletionWaitsForProcessingAndLaterDeliveryCannotRecreateThumbnail() throws Exception {
        seedMetadata();
        CountDownLatch processing = new CountDownLatch(1);
        CountDownLatch releaseProcessing = new CountDownLatch(1);
        CountDownLatch deleteStarted = new CountDownLatch(1);
        AtomicInteger writes = new AtomicInteger();

        try (var executor = Executors.newFixedThreadPool(2)) {
            var worker = executor.submit(() -> {
                coordinator.process("photo.jpg", () -> {
                    processing.countDown();
                    assertTrue(releaseProcessing.await(10, TimeUnit.SECONDS));
                    writes.incrementAndGet();
                });
                return null;
            });
            assertTrue(processing.await(10, TimeUnit.SECONDS));
            var deletion = executor.submit(() -> new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
                deleteStarted.countDown();
                repository.findFirstByS3Key("photo.jpg").ifPresent(repository::delete);
            }));
            assertTrue(deleteStarted.await(10, TimeUnit.SECONDS));
            assertThrows(TimeoutException.class, () -> deletion.get(200, TimeUnit.MILLISECONDS));
            releaseProcessing.countDown();
            worker.get(10, TimeUnit.SECONDS);
            deletion.get(10, TimeUnit.SECONDS);
        } finally {
            releaseProcessing.countDown();
        }
        assertFalse(repository.existsById("row"));

        var service = new AzureBlobFileProcessingService(container, repository, coordinator);
        var context = mock(ServiceBusReceivedMessageContext.class);
        service.processImage(new ImageProcessingMessage("photo.jpg", "image/jpeg", "s3", 10), context);
        verify(context).deadLetter();
        verify(context, never()).complete();
        assertEquals(1, writes.get());
    }

    @Test
    void processingFailureRollsBackMetadataChanges() {
        seedMetadata();
        assertThrows(IOException.class, () -> coordinator.process("photo.jpg", () -> {
            ImageMetadata metadata = repository.findFirstByS3Key("photo.jpg").orElseThrow();
            metadata.setThumbnailKey("photo_thumbnail.jpg");
            repository.saveAndFlush(metadata);
            throw new IOException("processing failed");
        }));
        assertNull(repository.findById("row").orElseThrow().getThumbnailKey());
    }
}
