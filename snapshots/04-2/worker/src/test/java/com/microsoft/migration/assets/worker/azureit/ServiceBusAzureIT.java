package com.microsoft.migration.assets.worker.azureit;

import com.azure.core.util.BinaryData;
import com.azure.messaging.servicebus.ServiceBusClientBuilder;
import com.azure.messaging.servicebus.ServiceBusMessage;
import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import com.microsoft.migration.assets.worker.service.BlobFileProcessingService;
import com.microsoft.migration.assets.worker.util.StorageUtil;
import org.junit.jupiter.api.Test;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ServiceBusAzureIT {
    @Test
    void processesOwnSessionMessageAndCompletesIt() throws Exception {
        AzureItContext context = new AzureItContext();
        String id = UUID.randomUUID().toString();
        String key = "azure-it/" + id + "/original.png";
        String thumbnail = StorageUtil.getThumbnailKey(key);
        System.out.println("Azure IT retained original: " + key);
        System.out.println("Azure IT retained thumbnail: " + thumbnail);
        System.out.println("Azure IT message/session ID: " + id);
        var container = context.container();
        assertNull(container.getProperties().getBlobPublicAccess(), "Container permits anonymous access");
        var image = new BufferedImage(4, 4, BufferedImage.TYPE_INT_RGB);
        var data = new ByteArrayOutputStream();
        assertTrue(ImageIO.write(image, "png", data));
        byte[] bytes = data.toByteArray();
        container.getBlobClient(key).upload(new ByteArrayInputStream(bytes), bytes.length, false);

        var payload = new ImageProcessingMessage(key, "image/png", "local", bytes.length);
        var message = new ServiceBusMessage(BinaryData.fromString(new ObjectMapper().writeValueAsString(payload)))
            .setMessageId(id).setSessionId(id).setContentType("application/json");
        var builder = new ServiceBusClientBuilder().fullyQualifiedNamespace(context.namespace()).credential(context.credential);
        try (var sender = builder.sender().queueName(context.get("AZURE_IT_SERVICEBUS_QUEUE")).buildClient();
             var sessions = builder.sessionReceiver().queueName(context.get("AZURE_IT_SERVICEBUS_QUEUE"))
                 .disableAutoComplete().buildClient()) {
            sender.sendMessage(message);
            try (var receiver = sessions.acceptSession(id)) {
                var iterator = receiver.receiveMessages(1, Duration.ofSeconds(30)).iterator();
                assertTrue(iterator.hasNext(), "Own test message was not received");
                var received = iterator.next();
                assertEquals(id, received.getMessageId(), "Unexpected message; it was not settled");
                assertEquals(id, received.getSessionId());
                var parsed = new ObjectMapper().readValue(received.getBody().toString(), ImageProcessingMessage.class);
                assertEquals(key, parsed.getKey());
                var settlement = mock(ServiceBusReceivedMessageContext.class);
                var completeCount = new AtomicInteger();
                var deadLetterCount = new AtomicInteger();
                doAnswer(invocation -> { receiver.complete(received); completeCount.incrementAndGet(); return null; })
                    .when(settlement).complete();
                doAnswer(invocation -> { receiver.deadLetter(received); deadLetterCount.incrementAndGet(); return null; })
                    .when(settlement).deadLetter();
                new BlobFileProcessingService(container).processImage(parsed, settlement);
                assertEquals(1, completeCount.get(), "Worker did not successfully complete the message");
                assertEquals(0, deadLetterCount.get(), "Worker dead-lettered the test message");
                var output = new ByteArrayOutputStream();
                container.getBlobClient(thumbnail).downloadStream(output);
                assertNotNull(ImageIO.read(new ByteArrayInputStream(output.toByteArray())), "Thumbnail is not a readable image");
            }
        }
    }
}
