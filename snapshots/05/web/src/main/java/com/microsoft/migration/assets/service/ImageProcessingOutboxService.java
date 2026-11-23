package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.microsoft.migration.assets.config.BackupQueue;
import com.microsoft.migration.assets.model.ImageMetadata;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.ImageProcessingOutbox;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import com.microsoft.migration.assets.repository.ImageProcessingOutboxRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;

@Service
@Profile("!dev")
@RequiredArgsConstructor
@Slf4j
public class ImageProcessingOutboxService {
    private final ImageMetadataRepository metadataRepository;
    private final ImageProcessingOutboxRepository outboxRepository;
    private final ServiceBusTemplate serviceBusTemplate;
    private final Optional<BackupQueue> backupQueue;

    @Transactional
    public void recordUpload(ImageMetadata metadata, ImageProcessingMessage message) {
        metadataRepository.save(metadata);
        outboxRepository.save(new ImageProcessingOutbox(message, IMAGE_PROCESSING_QUEUE));
        backupQueue.ifPresent(queue -> outboxRepository.save(new ImageProcessingOutbox(message, queue.name())));
    }

    @Service
    @Profile("!dev")
    @ConditionalOnProperty(name = "assets.outbox.publisher.enabled", havingValue = "true", matchIfMissing = true)
    @RequiredArgsConstructor
    public static class Publisher {
        private final ImageProcessingOutboxService outboxService;

        @Scheduled(fixedDelayString = "${assets.outbox.publisher.delay-ms:5000}")
        public void publish() {
            outboxService.publishPending();
        }
    }

    @Transactional
    public void publishPending() {
        for (ImageProcessingOutbox entry : outboxRepository.findTop50ByNextAttemptAtLessThanEqualOrderByCreatedAtAsc(Instant.now())) {
            try {
                serviceBusTemplate.send(entry.getDestination(), MessageBuilder.withPayload(entry.toMessage()).build());
                outboxRepository.delete(entry);
            } catch (RuntimeException e) {
                entry.retryAfter(Instant.now().plus(30, ChronoUnit.SECONDS));
                outboxRepository.save(entry);
                log.error("Failed to publish image processing request {}; it remains pending", entry.getId(), e);
            }
        }
    }
}
