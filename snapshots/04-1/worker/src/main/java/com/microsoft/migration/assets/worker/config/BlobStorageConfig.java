package com.microsoft.migration.assets.worker.config;

import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Provides the {@link BlobContainerClient} bean used by both thumbnail backends in this module
 * for their shared private Azure Blob Storage container: the dev-profile
 * {@code BlobFileProcessingService} and the non-dev/object-storage-profile
 * {@code AzureBlobFileProcessingService} (which previously used Amazon S3). Since the two
 * profiles are mutually exclusive at runtime, both can safely share the same client/container
 * configuration.
 * <p>
 * The underlying {@link BlobServiceClient} bean is created by the
 * {@code spring-cloud-azure-starter-storage-blob} auto-configuration using the
 * {@code spring.cloud.azure.storage.blob.*} / {@code spring.cloud.azure.credential.*} properties
 * (see application.properties) - authentication is Azure Managed Identity (passwordless); no
 * account key or connection string is used anywhere in this module.
 * <p>
 * The container must already exist and this bean never generates a SAS URL.
 */
@Configuration
public class BlobStorageConfig {

    @Value("${azure.storage.blob.container-name}")
    private String containerName;

    @Bean
    public BlobContainerClient blobContainerClient(BlobServiceClient blobServiceClient) {
        BlobContainerClient containerClient = blobServiceClient.getBlobContainerClient(containerName);
        if (!containerClient.exists()) {
            throw new IllegalStateException("Blob container does not exist: " + containerName);
        }
        return containerClient;
    }
}
