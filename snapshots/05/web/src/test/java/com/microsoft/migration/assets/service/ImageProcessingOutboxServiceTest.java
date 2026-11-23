package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.microsoft.migration.assets.config.BackupQueue;
import com.microsoft.migration.assets.model.ImageMetadata;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.ImageProcessingOutbox;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import com.microsoft.migration.assets.repository.ImageProcessingOutboxRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.never;

@DataJpaTest
@Import(ImageProcessingOutboxService.class)
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class ImageProcessingOutboxServiceTest {
    @Autowired private ImageProcessingOutboxService service;
    @Autowired private ImageMetadataRepository metadataRepository;
    @Autowired private ImageProcessingOutboxRepository outboxRepository;
    @Autowired private PlatformTransactionManager transactionManager;
    @MockitoBean private ServiceBusTemplate serviceBusTemplate;

    @BeforeEach
    void cleanDatabase() {
        outboxRepository.deleteAll();
        metadataRepository.deleteAll();
    }

    private ImageMetadata metadata() {
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId(UUID.randomUUID().toString());
        metadata.setFilename("photo.jpg");
        metadata.setS3Key("photo.jpg");
        return metadata;
    }

    @Test
    void metadataAndOutboxRollbackTogether() {
        assertThrows(IllegalStateException.class, () -> new TransactionTemplate(transactionManager)
                .executeWithoutResult(status -> {
                    service.recordUpload(metadata(), new ImageProcessingMessage("photo.jpg", "image/jpeg", "azure-blob", 10));
                    throw new IllegalStateException("rollback");
                }));
        assertEquals(0, metadataRepository.count());
        assertEquals(0, outboxRepository.count());
    }

    @Test
    void failedPublishRemainsPendingAndIsRetried() {
        service.recordUpload(metadata(), new ImageProcessingMessage("photo.jpg", "image/jpeg", "azure-blob", 10));
        doThrow(new IllegalStateException("unavailable")).when(serviceBusTemplate).send(any(), any());
        service.publishPending();
        assertEquals(1, metadataRepository.count());
        assertEquals(1, outboxRepository.count());

        ImageProcessingOutbox pending = outboxRepository.findAll().get(0);
        pending.retryAfter(Instant.EPOCH);
        outboxRepository.save(pending);
        reset(serviceBusTemplate);
        doNothing().when(serviceBusTemplate).send(any(), any());
        service.publishPending();
        verify(serviceBusTemplate, times(1)).send(any(), any());
        assertEquals(0, outboxRepository.count());
    }

    @Test
    void backupAndPrimaryHaveIndependentPendingEntries() {
        ImageMetadataRepository metadata = mock(ImageMetadataRepository.class);
        ImageProcessingOutboxRepository outbox = mock(ImageProcessingOutboxRepository.class);
        ServiceBusTemplate bus = mock(ServiceBusTemplate.class);
        ImageProcessingOutboxService withBackup = new ImageProcessingOutboxService(metadata, outbox, bus,
                Optional.of(new BackupQueue("backup-monitoring")));
        withBackup.recordUpload(metadata(), new ImageProcessingMessage("photo.jpg", "image/jpeg", "azure-blob", 10));

        ArgumentCaptor<ImageProcessingOutbox> captor = ArgumentCaptor.forClass(ImageProcessingOutbox.class);
        verify(outbox, times(2)).save(captor.capture());
        List<ImageProcessingOutbox> entries = captor.getAllValues();
        assertEquals("image-processing", entries.get(0).getDestination());
        assertEquals("backup-monitoring", entries.get(1).getDestination());
        when(outbox.findTop50ByNextAttemptAtLessThanEqualOrderByCreatedAtAsc(any())).thenReturn(entries);
        doThrow(new IllegalStateException("unavailable")).when(bus).send(eq("backup-monitoring"), any());
        withBackup.publishPending();
        verify(outbox).delete(entries.get(0));
        verify(outbox, never()).delete(entries.get(1));
    }
}
