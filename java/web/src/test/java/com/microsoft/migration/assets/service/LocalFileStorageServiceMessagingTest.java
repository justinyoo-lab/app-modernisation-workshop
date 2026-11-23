package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.Message;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.file.Path;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * Producer-side unit tests for the local-storage (dev profile) upload path. {@link ServiceBusTemplate}
 * is mocked: no real Service Bus namespace is contacted.
 */
@ExtendWith(MockitoExtension.class)
class LocalFileStorageServiceMessagingTest {

    @Mock
    private ServiceBusTemplate serviceBusTemplate;

    @TempDir
    Path tempDir;

    private LocalFileStorageService localFileStorageService;

    @BeforeEach
    void setUp() throws Exception {
        localFileStorageService = new LocalFileStorageService(serviceBusTemplate);
        ReflectionTestUtils.setField(localFileStorageService, "storageDirectory", tempDir.toString());
        localFileStorageService.init();
    }

    @Test
    void uploadPublishesMessageToImageProcessingQueue() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        localFileStorageService.uploadObject(file);

        ArgumentCaptor<Message<ImageProcessingMessage>> captor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), captor.capture());
        ImageProcessingMessage payload = captor.getValue().getPayload();
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals("local", payload.getStorageType());
    }

    @Test
    void duplicateUploadsEachPublishAnIndependentMessage() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "photo.jpg", "image/jpeg", "sample-bytes".getBytes());

        localFileStorageService.uploadObject(file);
        localFileStorageService.uploadObject(file);

        verify(serviceBusTemplate, times(2)).send(eq(IMAGE_PROCESSING_QUEUE), any());
    }
}
