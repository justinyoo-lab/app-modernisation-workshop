package com.microsoft.migration.assets.worker.service;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.FileNotFoundException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;

/**
 * Consumer-side unit tests for {@link AbstractFileProcessingService}, covering the success,
 * duplicate-delivery, dead-letter, and graceful-shutdown paths of the RabbitMQ -&gt; Azure Service
 * Bus migration. {@link ServiceBusReceivedMessageContext} is mocked throughout: no real Service
 * Bus namespace is contacted.
 */
class AbstractFileProcessingServiceTest {

    @TempDir
    Path tempDir;

    private Path writeSampleImage(String filename) throws Exception {
        Path file = tempDir.resolve(filename);
        BufferedImage image = new BufferedImage(20, 20, BufferedImage.TYPE_INT_RGB);
        ImageIO.write(image, "jpg", file.toFile());
        return file;
    }

    /** Minimal test double backed by a local directory instead of a real remote object store. */
    private static class TestFileProcessingService extends AbstractFileProcessingService {
        private final Path sourceDir;
        private boolean failDownload;

        TestFileProcessingService(Path sourceDir) {
            this.sourceDir = sourceDir;
        }

        @Override
        public void downloadOriginal(String key, Path destination) throws Exception {
            if (failDownload) {
                throw new FileNotFoundException("missing: " + key);
            }
            Files.copy(sourceDir.resolve(key), destination);
        }

        @Override
        public void uploadThumbnail(Path source, String key, String contentType) {
            // no-op: the thumbnail destination is irrelevant to the messaging behavior under test
        }

        @Override
        public String getStorageType() {
            return "local";
        }

        @Override
        protected String generateUrl(String key) {
            return "/storage/" + key;
        }
    }

    @Test
    void successfulProcessingCompletesTheMessage() throws Exception {
        writeSampleImage("photo.jpg");
        TestFileProcessingService service = new TestFileProcessingService(tempDir);
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "local", 10);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        verify(context, times(1)).complete();
        verify(context, never()).abandon();
        verify(context, never()).deadLetter();
    }

    @Test
    void duplicateDeliveryIsProcessedIdempotentlyAndEachCopyIsCompleted() throws Exception {
        // At-least-once delivery can redeliver the same logical message twice, each on its own
        // receive context; reprocessing must remain safe and each copy must be completed.
        writeSampleImage("photo.jpg");
        TestFileProcessingService service = new TestFileProcessingService(tempDir);
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "local", 10);
        ServiceBusReceivedMessageContext firstDelivery = mock(ServiceBusReceivedMessageContext.class);
        ServiceBusReceivedMessageContext secondDelivery = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, firstDelivery);
        service.processImage(message, secondDelivery);

        verify(firstDelivery, times(1)).complete();
        verify(secondDelivery, times(1)).complete();
    }

    @Test
    void failedDownloadDeadLettersTheMessageWithoutCompleting() throws Exception {
        // Equivalent to the original channel.basicNack(deliveryTag, false, false) with requeue=false:
        // the message is routed straight to the dead-letter path, not redelivered by this listener.
        TestFileProcessingService service = new TestFileProcessingService(tempDir);
        service.failDownload = true;
        ImageProcessingMessage message = new ImageProcessingMessage("missing.jpg", "image/jpeg", "local", 10);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        service.processImage(message, context);

        verify(context, times(1)).deadLetter();
        verify(context, never()).complete();
        verify(context, never()).abandon();
        verifyNoMoreInteractions(context);
    }

    @Test
    void missingReceiveContextDuringGracefulShutdownDoesNotThrow() throws Exception {
        // During processor shutdown the message-handling pipeline may not resolve a receive context
        // for an in-flight message; the listener must still run its cleanup logic without throwing.
        writeSampleImage("photo.jpg");
        TestFileProcessingService service = new TestFileProcessingService(tempDir);
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "local", 10);

        assertDoesNotThrow(() -> service.processImage(message, null));
    }
}
