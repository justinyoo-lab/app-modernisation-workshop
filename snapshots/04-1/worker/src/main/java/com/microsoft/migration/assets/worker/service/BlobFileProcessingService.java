package com.microsoft.migration.assets.worker.service;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

import java.io.FileNotFoundException;
import java.nio.file.Path;

/**
 * Dev-profile thumbnail storage backend. Previously persisted original/thumbnail images to the
 * local filesystem via Java NIO under a "../storage" directory; now persists to a private Azure
 * Blob Storage container through the managed-identity-authenticated {@link BlobContainerClient}
 * configured in {@link com.microsoft.migration.assets.worker.config.BlobStorageConfig}.
 * <p>
 * The storage type reported to {@code AbstractFileProcessingService} (used to match the Service
 * Bus message's storage type to this implementation) stays {@code "local"}, matching
 * {@code BlobFileStorageService} in the web module. The blob container is never made
 * publicly/anonymously accessible, and no SAS URL (time-limited or indefinite) is ever generated.
 */
@Service
@Profile("dev")
public class BlobFileProcessingService extends AbstractFileProcessingService {

    private static final Logger logger = LoggerFactory.getLogger(BlobFileProcessingService.class);

    private final BlobContainerClient blobContainerClient;

    public BlobFileProcessingService(BlobContainerClient blobContainerClient) {
        this.blobContainerClient = blobContainerClient;
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
    }

    @Override
    public String getStorageType() {
        return "local";
    }

    @Override
    protected String generateUrl(String key) {
        // Dev-profile thumbnails are never exposed via a Blob SAS URL (no public access, no
        // indefinite SAS). The web application streams bytes through its own controller instead;
        // this app-relative path mirrors the previous local-storage implementation's behavior.
        return "/storage/" + key;
    }
}
