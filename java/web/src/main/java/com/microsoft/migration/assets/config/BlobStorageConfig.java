package com.microsoft.migration.assets.config;

import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Provides the {@link BlobContainerClient} bean used by the dev-profile storage backend
 * ({@code BlobFileStorageService}) for its private Azure Blob Storage container.
 * <p>
 * The underlying {@link BlobServiceClient} bean is created by the
 * {@code spring-cloud-azure-starter-storage-blob} auto-configuration using the
 * {@code spring.cloud.azure.storage.blob.*} / {@code spring.cloud.azure.credential.*} properties
 * (see application.properties) - authentication is Azure Managed Identity (passwordless); no
 * account key or connection string is used anywhere in this module.
 * <p>
 * The container is only ever created private (no {@code PublicAccessType} is set, so anonymous
 * access stays disabled) and this bean never generates a SAS URL - callers stream bytes through
 * the application instead (see {@code BlobFileStorageService}/{@code S3Controller}).
 * <p>
 * This bean/config is intentionally reusable: a future migration of the non-dev AWS S3 path to
 * Blob Storage can inject the same {@link BlobContainerClient} (or add a sibling bean here) rather
 * than duplicating client setup.
 */
@Configuration
public class BlobStorageConfig {

    private static final Logger logger = LoggerFactory.getLogger(BlobStorageConfig.class);

    @Value("${azure.storage.blob.container-name}")
    private String containerName;

    @Bean
    public BlobContainerClient blobContainerClient(BlobServiceClient blobServiceClient) {
        BlobContainerClient containerClient = blobServiceClient.getBlobContainerClient(containerName);
        try {
            if (!containerClient.exists()) {
                // Deliberately does not set a PublicAccessType: the container is created private.
                containerClient.create();
                logger.info("Created private blob container: {}", containerName);
            }
        } catch (Exception e) {
            // The managed identity may only be granted least-privilege Blob Data
            // Contributor/Reader permissions on an already-provisioned container (no
            // container-management rights). Logging and continuing mirrors the previous local-file
            // behavior of best-effort "create directory if missing" without requiring elevated
            // permissions, and without failing application startup.
            logger.warn("Could not verify/create blob container '{}' (it may already exist or be " +
                    "managed by infrastructure): {}", containerName, e.getMessage());
        }
        return containerClient;
    }
}
