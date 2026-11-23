package com.microsoft.migration.assets.service;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobStorageException;
import com.microsoft.migration.assets.model.ImageMetadata;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.model.S3StorageItem;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import lombok.RequiredArgsConstructor;
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
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;

/**
 * Non-dev-profile ("object storage") backend. Previously persisted uploads to Amazon S3 via the
 * AWS SDK; now persists to the same private Azure Blob Storage container (provisioned/authenticated
 * by Azure Managed Identity) that backs the dev-profile {@link BlobFileStorageService}, through the
 * shared {@link BlobContainerClient} bean configured in
 * {@link com.microsoft.migration.assets.config.BlobStorageConfig}.
 * <p>
 * Preserves the non-dev-profile behavior verified in the Phase 1 baseline (distinct from the
 * dev/local path):
 * <ul>
 *     <li>uploads create exactly one {@code image_metadata} row, keyed by the generated object
 *     key ({@code s3Key});</li>
 *     <li>deletes remove both the original and thumbnail objects (best-effort for the thumbnail)
 *     and the corresponding {@code image_metadata} row;</li>
 *     <li>list resolves each object's {@code uploadedAt} from {@code image_metadata} when a
 *     matching row exists, falling back to the object's last-modified time otherwise;</li>
 *     <li>the generated "key" convention ({@code <uuid>-<original-filename>} and
 *     {@code <uuid>-<name>_thumbnail.<ext>}) is unchanged.</li>
 * </ul>
 * The blob container is never made publicly/anonymously accessible, and no SAS URL (time-limited
 * or indefinite) is ever generated: bytes are always streamed back through {@link #getObject},
 * which {@code S3Controller} exposes at {@code /storage/view/{key}} (see
 * {@link StorageService#generateUrl(String)}). Caller-supplied keys are validated through
 * {@link BlobKeyValidator} before being used to address a blob, closing the resource-injection gap
 * (CWE-99) that existed in the previous implementation, where a key derived from user input was
 * passed straight into the storage SDK without any normalization/containment check.
 */
@Service
@RequiredArgsConstructor
@Profile("!dev") // Active when not in dev profile
public class AzureBlobService implements StorageService {

    private static final Logger logger = LoggerFactory.getLogger(AzureBlobService.class);

    private final BlobContainerClient blobContainerClient;
    private final ServiceBusTemplate serviceBusTemplate;
    private final ImageMetadataRepository imageMetadataRepository;

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
        String key = blobItem.getName();
        Instant lastModified = blobItem.getProperties().getLastModified() != null
                ? blobItem.getProperties().getLastModified().toInstant()
                : null;
        Long contentLength = blobItem.getProperties().getContentLength();
        long size = contentLength != null ? contentLength : 0L;

        // Try to get metadata for upload time
        Instant uploadedAt = imageMetadataRepository.findAll().stream()
                .filter(metadata -> metadata.getS3Key().equals(key))
                .map(metadata -> metadata.getUploadedAt().atZone(ZoneId.systemDefault()).toInstant())
                .findFirst()
                .orElse(lastModified); // fallback to lastModified if metadata not found

        return new S3StorageItem(key, extractFilename(key), size, lastModified, uploadedAt, generateUrl(key));
    }

    @Override
    public void uploadObject(MultipartFile file) throws IOException {
        if (file.isEmpty()) {
            throw new IOException("Failed to store empty file");
        }

        // Reject anything that is not an allowlisted image type before it is stored or queued
        // for thumbnail processing (CWE-434: Unrestricted Upload of File with Dangerous Type).
        UploadedFileValidator.validate(file);

        // Validate/sanitize the caller-supplied filename *before* it is combined with the
        // generated UUID prefix. Validating only the final concatenated key would be unsafe: a
        // malicious filename such as "../../secret.jpg" can be collapsed by path normalization
        // once prefixed with "<uuid>-" (the leading ".." segments get cancelled out by the
        // preceding non-".." segment), silently defeating the check. Sanitizing the raw filename
        // first closes this resource-injection gap (CWE-99).
        String sanitizedFilename = BlobKeyValidator.sanitize(file.getOriginalFilename());
        String sanitizedKey = generateKey(sanitizedFilename);

        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        try (InputStream inputStream = file.getInputStream()) {
            blobClient.upload(inputStream, file.getSize(), true);
        } catch (BlobStorageException e) {
            throw new IOException("Failed to upload blob: " + sanitizedKey, e);
        }
        if (file.getContentType() != null) {
            blobClient.setHttpHeaders(new BlobHttpHeaders().setContentType(file.getContentType()));
        }
        logger.info("Stored blob: {}", sanitizedKey);

        // Send message to queue for thumbnail generation
        ImageProcessingMessage message = new ImageProcessingMessage(
                sanitizedKey,
                file.getContentType(),
                getStorageType(),
                file.getSize()
        );
        Message<ImageProcessingMessage> serviceBusMessage = MessageBuilder.withPayload(message).build();
        serviceBusTemplate.send(IMAGE_PROCESSING_QUEUE, serviceBusMessage);

        // Create and save metadata to database
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId(UUID.randomUUID().toString());
        metadata.setFilename(file.getOriginalFilename());
        metadata.setContentType(file.getContentType());
        metadata.setSize(file.getSize());
        metadata.setS3Key(sanitizedKey);
        metadata.setS3Url(generateUrl(sanitizedKey));

        imageMetadataRepository.save(metadata);
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
        String sanitizedKey = BlobKeyValidator.sanitize(key);

        // Delete both original and thumbnail if it exists
        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        blobClient.deleteIfExists();

        try {
            // Try to delete thumbnail if it exists
            String thumbnailKey = getThumbnailKey(sanitizedKey);
            blobContainerClient.getBlobClient(thumbnailKey).deleteIfExists();
        } catch (Exception e) {
            // Ignore if thumbnail doesn't exist or can't be deleted
            logger.warn("Could not delete thumbnail for {}: {}", sanitizedKey, e.getMessage());
        }

        // Delete metadata from database
        imageMetadataRepository.findAll().stream()
                .filter(metadata -> metadata.getS3Key().equals(sanitizedKey))
                .findFirst()
                .ifPresent(imageMetadataRepository::delete);
    }

    @Override
    public String getStorageType() {
        return "azure-blob";
    }

    private String extractFilename(String key) {
        // Extract filename from the object key
        int lastSlashIndex = key.lastIndexOf('/');
        return lastSlashIndex >= 0 ? key.substring(lastSlashIndex + 1) : key;
    }

    private String generateKey(String filename) {
        return UUID.randomUUID().toString() + "-" + filename;
    }
}
