package com.microsoft.migration.assets.worker.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import com.microsoft.migration.assets.worker.repository.ImageMetadataRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.io.FileNotFoundException;
import java.nio.file.Path;

/**
 * Non-dev-profile ("object storage") thumbnail backend. Previously persisted original/thumbnail
 * images to Amazon S3 via the AWS SDK; now persists to the same private Azure Blob Storage
 * container (provisioned/authenticated by Azure Managed Identity) that backs the dev-profile
 * {@link BlobFileProcessingService}, through the shared {@link BlobContainerClient} bean
 * configured in {@link com.microsoft.migration.assets.worker.config.BlobStorageConfig}.
 * <p>
 * The storage type reported to {@code AbstractFileProcessingService} (used to match the Service
 * Bus message's storage type to this implementation) matches
 * {@code AzureBlobService#getStorageType()} in the web module ({@code "azure-blob"}). Preserves
 * the non-dev-profile behavior verified in the Phase 1 baseline: after a thumbnail is uploaded,
 * the matching {@code image_metadata} row (looked up by original {@code s3Key}) is updated with
 * the thumbnail key/URL.
 * <p>
 * The blob container is never made publicly/anonymously accessible, and no SAS URL (time-limited
 * or indefinite) is ever generated. Caller-supplied keys (both the original key received from the
 * Service Bus message and the derived thumbnail key) are validated through
 * {@link BlobKeyValidator} before being used to address a blob, closing the resource-injection gap
 * (CWE-99) that existed in the previous implementation, where a key coming off the queue was
 * passed straight into the storage SDK without any normalization/containment check.
 */
@Service
@Profile("!dev")
@RequiredArgsConstructor
public class AzureBlobFileProcessingService extends AbstractFileProcessingService {

    private static final Logger logger = LoggerFactory.getLogger(AzureBlobFileProcessingService.class);

    private final BlobContainerClient blobContainerClient;
    private final ImageMetadataRepository imageMetadataRepository;
    private final ImageProcessingCoordinator coordinator;

    @Override
    protected void processWithCoordination(ImageProcessingMessage message, ProcessingAction action) throws Exception {
        coordinator.process(BlobKeyValidator.sanitize(message.getKey()), action);
    }

    @Override
    public void downloadOriginal(String key, Path destination) throws Exception {
        String sanitizedKey = BlobKeyValidator.sanitize(key);
        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        if (!blobClient.exists()) {
            throw new FileNotFoundException("Blob not found: " + sanitizedKey);
        }
        blobClient.downloadToFile(destination.toString(), true);
        logger.info("Downloaded blob {} to {}", sanitizedKey, destination);
    }

    @Override
    public void uploadThumbnail(Path source, String key, String contentType) throws Exception {
        String sanitizedKey = BlobKeyValidator.sanitize(key);
        BlobClient blobClient = blobContainerClient.getBlobClient(sanitizedKey);
        blobClient.uploadFromFile(source.toString(), true);
        if (contentType != null) {
            blobClient.setHttpHeaders(new BlobHttpHeaders().setContentType(contentType));
        }
        logger.info("Uploaded thumbnail blob: {}", sanitizedKey);

        // Extract the original key from the thumbnail key
        String originalKey = extractOriginalKey(sanitizedKey);

        // Find and update metadata
        var metadata = imageMetadataRepository.findAll().stream()
                .filter(item -> item.getS3Key().equals(originalKey))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Metadata not found for blob: " + originalKey));
        metadata.setThumbnailKey(sanitizedKey);
        metadata.setThumbnailUrl(generateUrl(sanitizedKey));
        imageMetadataRepository.save(metadata);
    }

    @Override
    public String getStorageType() {
        return "azure-blob";
    }

    @Override
    protected boolean matchesStorageType(String messageStorageType) {
        // Accept both the current "azure-blob" literal and the legacy "s3" literal still produced
        // by callers/messages predating the Azure Blob Storage migration, preserving the
        // ImageProcessingMessage contract's backward compatibility.
        return "azure-blob".equals(messageStorageType) || "s3".equals(messageStorageType);
    }

    @Override
    protected String generateUrl(String key) {
        // Non-dev-profile thumbnails are never exposed via a Blob SAS URL (no public access, no
        // indefinite SAS). The web application streams bytes through its own controller instead;
        // this app-relative path mirrors the dev-profile BlobFileProcessingService's behavior and
        // the StorageService#generateUrl default used elsewhere in the web module.
        return "/storage/view/" + key;
    }

    private String extractOriginalKey(String key) {
        // For a key like "xxxxx_thumbnail.png", get "xxxxx.png"
        String suffix = "_thumbnail";
        int extensionIndex = key.lastIndexOf('.');
        if (extensionIndex > 0) {
            String nameWithoutExtension = key.substring(0, extensionIndex);
            String extension = key.substring(extensionIndex);

            int suffixIndex = nameWithoutExtension.lastIndexOf(suffix);
            if (suffixIndex > 0) {
                return nameWithoutExtension.substring(0, suffixIndex) + extension;
            }
        }
        if (key.endsWith(suffix)) {
            return key.substring(0, key.length() - suffix.length());
        }
        return key;
    }
}
