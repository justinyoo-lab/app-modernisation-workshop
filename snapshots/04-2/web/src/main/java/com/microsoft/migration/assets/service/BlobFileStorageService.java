package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobStorageException;
import com.microsoft.migration.assets.config.BackupQueue;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.S3StorageItem;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;

/**
 * Dev-profile storage backend. Previously persisted uploads to the local filesystem via Java NIO
 * under a "../storage" directory; now persists to a private Azure Blob Storage container through
 * the managed-identity-authenticated {@link BlobContainerClient} configured in
 * {@link com.microsoft.migration.assets.config.BlobStorageConfig}.
 * <p>
 * Preserves the original dev-profile behavior:
 * <ul>
 *     <li>uploads do not write an {@code image_metadata} database row - this is intentional
 *     dev-profile behavior, verified in the Phase 1 baseline, and still holds here;</li>
 *     <li>the storage type reported to the rest of the system (and used to route the Service Bus
 *     thumbnail-generation message to {@code BlobFileProcessingService}) stays {@code "local"};</li>
 *     <li>list/view/delete/thumbnail behavior is unchanged from the caller's point of view.</li>
 * </ul>
 * The blob container is never made publicly/anonymously accessible, and no SAS URL (time-limited
 * or indefinite) is ever generated: bytes are always streamed back through {@link #getObject},
 * which {@code S3Controller} exposes at {@code /storage/view/{key}}.
 */
@Service
@Profile("dev") // Only active when dev profile is active
public class BlobFileStorageService implements StorageService {

    private static final Logger logger = LoggerFactory.getLogger(BlobFileStorageService.class);

    private final ServiceBusTemplate serviceBusTemplate;
    private final BlobContainerClient blobContainerClient;
    private final Optional<BackupQueue> backupQueue;

    public BlobFileStorageService(ServiceBusTemplate serviceBusTemplate, BlobContainerClient blobContainerClient,
                                  Optional<BackupQueue> backupQueue) {
        this.serviceBusTemplate = serviceBusTemplate;
        this.blobContainerClient = blobContainerClient;
        this.backupQueue = backupQueue;
    }

    @Override
    public List<S3StorageItem> listObjects() {
        try {
            return blobContainerClient.listBlobs().stream()
                    .map(this::toStorageItem)
                    .collect(Collectors.toList());
        } catch (BlobStorageException e) {
            logger.error("Failed to list blobs", e);
            return List.of();
        }
    }

    private S3StorageItem toStorageItem(BlobItem blobItem) {
        String name = blobItem.getName();
        Instant lastModified = blobItem.getProperties().getLastModified() != null
                ? blobItem.getProperties().getLastModified().toInstant()
                : null;
        Instant createdOn = blobItem.getProperties().getCreationTime() != null
                ? blobItem.getProperties().getCreationTime().toInstant()
                : lastModified;
        Long contentLength = blobItem.getProperties().getContentLength();
        long size = contentLength != null ? contentLength : 0L;
        return new S3StorageItem(name, name, size, lastModified, createdOn, generateUrl(name));
    }

    @Override
    public void uploadObject(MultipartFile file) throws IOException {
        if (file.isEmpty()) {
            throw new IOException("Failed to store empty file");
        }

        // Reject anything that is not an allowlisted image type before it is stored or queued
        // for thumbnail processing (CWE-434: Unrestricted Upload of File with Dangerous Type).
        UploadedFileValidator.validate(file);

        String key = BlobKeyValidator.sanitize(file.getOriginalFilename());

        BlobClient blobClient = blobContainerClient.getBlobClient(key);
        try (InputStream inputStream = file.getInputStream()) {
            blobClient.upload(inputStream, file.getSize(), true);
        } catch (BlobStorageException e) {
            throw new IOException("Failed to upload blob: " + key, e);
        }
        if (file.getContentType() != null) {
            blobClient.setHttpHeaders(new BlobHttpHeaders().setContentType(file.getContentType()));
        }
        logger.info("Stored blob: {}", key);

        // Send message to queue for thumbnail generation
        ImageProcessingMessage message = new ImageProcessingMessage(
            key,
            file.getContentType(),
            getStorageType(),
            file.getSize()
        );
        Message<ImageProcessingMessage> serviceBusMessage = MessageBuilder.withPayload(message).build();
        serviceBusTemplate.send(IMAGE_PROCESSING_QUEUE, serviceBusMessage);
        if (backupQueue.isPresent()) {
            try {
                serviceBusTemplate.send(backupQueue.get().name(), serviceBusMessage);
            } catch (RuntimeException e) {
                throw new IOException("Image processing was queued, but backup monitoring could not be queued", e);
            }
        }
    }

    @Override
    public InputStream getObject(String key) throws IOException {
        String sanitizedKey = BlobKeyValidator.sanitize(key);
        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        if (!blobClient.exists()) {
            throw new FileNotFoundException("Blob not found: " + sanitizedKey);
        }
        return blobClient.downloadContent().toStream();
    }

    @Override
    public void deleteObject(String key) throws IOException {
        // Delete both original and thumbnail if it exists
        String sanitizedKey = BlobKeyValidator.sanitize(key);
        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        if (!blobClient.exists()) {
            throw new FileNotFoundException("File not found: " + sanitizedKey);
        }
        blobClient.delete();
        logger.info("Deleted blob: {}", sanitizedKey);

        // Try to delete thumbnail if it exists
        try {
            String thumbnailKey = getThumbnailKey(sanitizedKey);
            BlobClient thumbnailBlob = blobContainerClient.getBlobClient(thumbnailKey);
            if (thumbnailBlob.exists()) {
                thumbnailBlob.delete();
                logger.info("Deleted thumbnail blob: {}", thumbnailKey);
            }
        } catch (Exception e) {
            // Ignore if thumbnail doesn't exist or can't be deleted
            logger.warn("Could not delete thumbnail for {}: {}", sanitizedKey, e.getMessage());
        }
    }

    @Override
    public String getStorageType() {
        return "local";
    }
}
