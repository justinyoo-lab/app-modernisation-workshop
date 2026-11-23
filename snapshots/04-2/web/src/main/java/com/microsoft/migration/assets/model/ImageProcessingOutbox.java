package com.microsoft.migration.assets.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "image_processing_outbox")
@Getter
@NoArgsConstructor
public class ImageProcessingOutbox {
    @Id
    private String id;
    @Column(name = "blob_key", nullable = false, length = 512)
    private String key;
    private String contentType;
    @Column(nullable = false)
    private String storageType;
    @Column(nullable = false)
    private String destination;
    private long size;
    @Column(nullable = false)
    private Instant createdAt;
    @Column(nullable = false)
    private Instant nextAttemptAt;

    public ImageProcessingOutbox(ImageProcessingMessage message, String destination) {
        this.id = UUID.randomUUID().toString();
        this.key = message.getKey();
        this.contentType = message.getContentType();
        this.storageType = message.getStorageType();
        this.destination = destination;
        this.size = message.getSize();
        this.createdAt = Instant.now();
        this.nextAttemptAt = this.createdAt;
    }

    public ImageProcessingMessage toMessage() {
        return new ImageProcessingMessage(key, contentType, storageType, size);
    }

    public void retryAfter(Instant nextAttemptAt) {
        this.nextAttemptAt = nextAttemptAt;
    }
}
