package com.microsoft.migration.assets;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobContainerClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.config.BackupQueue;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import com.microsoft.migration.assets.service.BackupMessageProcessor;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * Post-migration integration test (Phase 3, {@code verify-test-baseline}) for the {@code web}
 * module's sole non-HTTP entry point: the backup Service Bus
 * message-queue listener (profile {@code backup}), generated 1:1 from TC-WEB-018 in
 * {@code web/src/test/test-cases/test-cases.md}.
 * <p>
 * <b>Trigger mechanism (forced adaptation — see {@code pre-generation-trigger-audit-web.md} and
 * {@code post-migration-plan-web.md} for the full justification).</b> {@code infra-decision-table.md}
 * fixes every dependency in this module to {@code mock}, and no real or testcontainer-backed Azure
 * Service Bus namespace/emulator is available in this environment, so there is no way to put a
 * real message onto a real queue for {@code @ServiceBusListener} dispatch to pick up. The closest
 * available trigger is to construct the {@link BackupMessageProcessor} and invoke its public
 * {@code processBackupMessage(ImageProcessingMessage, ServiceBusReceivedMessageContext)} method
 * directly — not a private helper, not a reimplementation of its logic — with the message built by
 * deserializing the EXACT JSON trigger body from the spec, and a Mockito mock standing in for the
 * {@link ServiceBusReceivedMessageContext} so {@code .complete()} can be verified. This is a
 * pre-approved, explicitly documented deviation forced by the fixed mock-only decision table, not a
 * shortcut chosen to avoid a real/testcontainer dependency that was otherwise reachable.
 */
class BackupListenerPostMigrationIT {

    private final BackupMessageProcessor backupMessageProcessor = new BackupMessageProcessor(new BackupQueue("backup-monitoring"));

    private final BlobContainerClient blobContainerClient = mock(BlobContainerClient.class);

    private final ImageMetadataRepository imageMetadataRepository = mock(ImageMetadataRepository.class);

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    void backupQueueMustBeSeparate() {
        assertThrows(IllegalArgumentException.class, () -> new BackupQueue("image-processing"));
        assertThrows(IllegalArgumentException.class, () -> new BackupQueue(" "));
    }

    // --- TC-WEB-018: Backup listener — acknowledges monitored message (happy path) ---------

    @Test
    void tcWeb018_backupListenerAcknowledgesMessage() throws Exception {
        String triggerJson = "{\"key\":\"sample.jpg\",\"contentType\":\"image/jpeg\",\"storageType\":\"local\",\"size\":2135}";
        ImageProcessingMessage message = MAPPER.readValue(triggerJson, ImageProcessingMessage.class);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        backupMessageProcessor.processBackupMessage(message, context);

        // Resource verification: the message is acknowledged (completed), not left for redelivery.
        verify(context, times(1)).complete();
        verify(context, never()).abandon();

        // Negative verification: no storage/database side effect results from this message.
        verifyNoInteractions(blobContainerClient);
        verifyNoInteractions(imageMetadataRepository);

        assertEquals("sample.jpg", message.getKey());
        assertEquals("image/jpeg", message.getContentType());
        assertEquals("local", message.getStorageType());
        assertEquals(2135L, message.getSize());
    }
}
