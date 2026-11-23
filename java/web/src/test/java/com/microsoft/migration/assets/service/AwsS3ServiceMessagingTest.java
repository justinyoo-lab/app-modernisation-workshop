package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.Message;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;
import software.amazon.awssdk.services.s3.S3Client;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * Producer-side unit tests for the RabbitMQ -&gt; Azure Service Bus migration. {@link ServiceBusTemplate}
 * is mocked throughout: these tests never connect to or provision a real Service Bus namespace.
 */
@ExtendWith(MockitoExtension.class)
class AwsS3ServiceMessagingTest {

    @Mock
    private S3Client s3Client;

    @Mock
    private ServiceBusTemplate serviceBusTemplate;

    @Mock
    private ImageMetadataRepository imageMetadataRepository;

    private AwsS3Service awsS3Service;

    @BeforeEach
    void setUp() {
        awsS3Service = new AwsS3Service(s3Client, serviceBusTemplate, imageMetadataRepository);
        ReflectionTestUtils.setField(awsS3Service, "bucketName", "test-bucket");
    }

    @Test
    void uploadPublishesSingleMessageToImageProcessingQueue() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        awsS3Service.uploadObject(file);

        ArgumentCaptor<Message<ImageProcessingMessage>> captor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), captor.capture());
        ImageProcessingMessage payload = captor.getValue().getPayload();
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals("s3", payload.getStorageType());
    }

    @Test
    void duplicateUploadsEachPublishAnIndependentMessage() throws Exception {
        // At-least-once delivery semantics mean the producer does not deduplicate; two logically
        // identical uploads (e.g. a client-side retry after an ambiguous network failure) must each
        // result in their own Service Bus message, with de-duplication left to the consumer.
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        awsS3Service.uploadObject(file);
        awsS3Service.uploadObject(file);

        verify(serviceBusTemplate, times(2)).send(eq(IMAGE_PROCESSING_QUEUE), any());
    }
}
