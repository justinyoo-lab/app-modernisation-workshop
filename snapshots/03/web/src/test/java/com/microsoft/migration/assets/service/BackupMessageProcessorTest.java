package com.microsoft.migration.assets.service;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * Consumer-side unit tests for {@link BackupMessageProcessor} covering the Azure Service Bus
 * migration's success, retry (abandon-and-redeliver), duplicate-delivery, and graceful-shutdown
 * paths. {@link ServiceBusReceivedMessageContext} is mocked throughout: no real Service Bus
 * namespace is contacted.
 */
class BackupMessageProcessorTest {

    private final BackupMessageProcessor processor = new BackupMessageProcessor();

    @Test
    void successfulMonitoringCompletesTheMessage() {
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "s3", 10);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);

        processor.processBackupMessage(message, context);

        verify(context, times(1)).complete();
        verify(context, never()).abandon();
    }

    @Test
    void acknowledgmentFailureAbandonsTheMessageForRetry() {
        // Equivalent to the original channel.basicNack(deliveryTag, false, true) with requeue=true:
        // the message is abandoned so Service Bus makes it available for immediate redelivery.
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "s3", 10);
        ServiceBusReceivedMessageContext context = mock(ServiceBusReceivedMessageContext.class);
        doThrow(new RuntimeException("ack failure")).when(context).complete();

        processor.processBackupMessage(message, context);

        verify(context, times(1)).complete();
        verify(context, times(1)).abandon();
    }

    @Test
    void duplicateDeliveryIsProcessedIndependentlyPerReceiveContext() {
        // At-least-once delivery can hand the backup processor the same logical message twice,
        // each with its own receive context; both must be acknowledged independently.
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "s3", 10);
        ServiceBusReceivedMessageContext firstDelivery = mock(ServiceBusReceivedMessageContext.class);
        ServiceBusReceivedMessageContext secondDelivery = mock(ServiceBusReceivedMessageContext.class);

        processor.processBackupMessage(message, firstDelivery);
        processor.processBackupMessage(message, secondDelivery);

        verify(firstDelivery, times(1)).complete();
        verify(secondDelivery, times(1)).complete();
    }

    @Test
    void missingReceiveContextDuringGracefulShutdownDoesNotThrow() {
        // During processor shutdown the message-handling pipeline may not resolve a receive context;
        // the listener must degrade gracefully instead of throwing.
        ImageProcessingMessage message = new ImageProcessingMessage("photo.jpg", "image/jpeg", "s3", 10);

        assertDoesNotThrow(() -> processor.processBackupMessage(message, null));
    }
}
