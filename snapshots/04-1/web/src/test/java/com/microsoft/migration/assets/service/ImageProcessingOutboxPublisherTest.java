package com.microsoft.migration.assets.service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.ScheduledAnnotationBeanPostProcessor;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;

class ImageProcessingOutboxPublisherTest {
    @TestConfiguration(proxyBeanMethods = false)
    @EnableScheduling
    @Import(ImageProcessingOutboxService.Publisher.class)
    static class PublisherTestConfiguration {
        @Bean
        ImageProcessingOutboxService outboxService() {
            return mock(ImageProcessingOutboxService.class);
        }
    }

    @Test
    void publisherRegistersScheduledTaskWithoutExternalClients() {
        new ApplicationContextRunner()
                .withUserConfiguration(PublisherTestConfiguration.class)
                .run(context -> assertEquals(1, context.getBean(ScheduledAnnotationBeanPostProcessor.class)
                        .getScheduledTasks().size()));
    }
}
