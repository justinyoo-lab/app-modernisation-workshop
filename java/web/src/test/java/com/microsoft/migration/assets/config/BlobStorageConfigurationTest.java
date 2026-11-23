package com.microsoft.migration.assets.config;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Verifies that the production dev-profile storage configuration for the web module targets
 * Azure Blob Storage using Azure Managed Identity (passwordless), that no account key or
 * connection string is stored in configuration, and that the previous local-filesystem
 * configuration ("local.storage.directory") no longer appears. This test only parses the
 * properties file; it never opens a network connection.
 */
class BlobStorageConfigurationTest {

    private Properties loadMainApplicationProperties() throws IOException {
        Path propertiesPath = Path.of("src", "main", "resources", "application.properties");
        Properties properties = new Properties();
        try (InputStream in = Files.newInputStream(propertiesPath)) {
            properties.load(in);
        }
        return properties;
    }

    @Test
    void noLocalFilesystemStorageConfigurationRemains() throws IOException {
        Properties properties = loadMainApplicationProperties();

        properties.stringPropertyNames().forEach(name ->
                assertFalse(name.toLowerCase().contains("local.storage"),
                        "no local.storage.* property should remain: " + name));
    }

    @Test
    void noAccountKeyOrConnectionStringIsConfiguredForBlobStorage() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertNull(properties.getProperty("spring.cloud.azure.storage.blob.account-key"),
                "no account key should be stored in application configuration");
        assertNull(properties.getProperty("spring.cloud.azure.storage.blob.connection-string"),
                "no connection string should be stored in application configuration");
        properties.stringPropertyNames().stream()
                .filter(name -> name.toLowerCase().contains("storage.blob"))
                .forEach(name ->
                        assertFalse(name.toLowerCase().contains("password") || name.toLowerCase().contains("secret")
                                        || name.toLowerCase().contains("account-key")
                                        || name.toLowerCase().contains("connection-string"),
                                "no password/secret/account-key/connection-string property should be " +
                                        "configured for blob storage: " + name));
    }

    @Test
    void managedIdentityAuthenticationIsSharedWithBlobStorage() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertEquals("true", properties.getProperty("spring.cloud.azure.credential.managed-identity-enabled"),
                "managed identity authentication must be enabled (shared across Azure clients, including Blob Storage)");
    }

    @Test
    void blobEndpointAndContainerNameAreExternalizedNotHardcoded() throws IOException {
        Properties properties = loadMainApplicationProperties();

        String endpoint = properties.getProperty("spring.cloud.azure.storage.blob.endpoint");
        assertTrue(endpoint != null && endpoint.startsWith("${") && endpoint.endsWith("}"),
                "the Blob Storage endpoint must be supplied via environment configuration, not hardcoded");

        String containerName = properties.getProperty("azure.storage.blob.container-name");
        assertTrue(containerName != null && containerName.startsWith("${"),
                "the blob container name must be supplied via environment configuration, not hardcoded");
    }
}
