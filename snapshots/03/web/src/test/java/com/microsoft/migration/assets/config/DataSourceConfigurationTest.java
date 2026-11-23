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
 * Verifies that the production datasource configuration for the web module
 * targets Azure Database for PostgreSQL Flexible Server over TLS using Azure
 * Managed Identity, and that no credential (password/secret) is stored in
 * configuration. This test only parses the properties file; it never opens a
 * database connection.
 */
class DataSourceConfigurationTest {

    private Properties loadMainApplicationProperties() throws IOException {
        Path propertiesPath = Path.of("src", "main", "resources", "application.properties");
        Properties properties = new Properties();
        try (InputStream in = Files.newInputStream(propertiesPath)) {
            properties.load(in);
        }
        return properties;
    }

    @Test
    void datasourceUrlTargetsAzurePostgresqlFlexibleServerOverTls() throws IOException {
        Properties properties = loadMainApplicationProperties();

        String url = properties.getProperty("spring.datasource.url");
        assertTrue(url != null && !url.isBlank(), "spring.datasource.url must be configured");
        assertTrue(url.contains(".postgres.database.azure.com"),
                "datasource URL must target Azure Database for PostgreSQL Flexible Server");
        assertTrue(url.contains("sslmode=require"), "datasource URL must require TLS");
        assertFalse(url.toLowerCase().contains("localhost"), "datasource URL must not point at localhost");
    }

    @Test
    void noDatabasePasswordIsConfigured() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertNull(properties.getProperty("spring.datasource.password"),
                "no password should be stored in application configuration");
        assertEquals("true", properties.getProperty("spring.datasource.azure.passwordless-enabled"),
                "passwordless authentication must be enabled");
    }

    @Test
    void managedIdentityAuthenticationIsEnabled() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertEquals("true", properties.getProperty("spring.cloud.azure.credential.managed-identity-enabled"),
                "managed identity authentication must be enabled for the datasource");
    }

    @Test
    void applicationDatabasePrincipalIsExternalizedNotHardcoded() throws IOException {
        Properties properties = loadMainApplicationProperties();

        String username = properties.getProperty("spring.datasource.username");
        assertTrue(username != null && username.startsWith("${") && username.endsWith("}"),
                "the application database principal must be supplied via environment configuration, "
                        + "not hardcoded in the properties file");
        assertFalse("postgres".equalsIgnoreCase(username), "a generic/admin principal must not be hardcoded");
    }
}
