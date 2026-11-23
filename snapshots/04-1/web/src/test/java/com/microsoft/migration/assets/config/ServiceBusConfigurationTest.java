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
 * Verifies that the production messaging configuration for the web module targets Azure Service
 * Bus using Azure Managed Identity (passwordless), and that no connection string, key, or secret
 * is stored in configuration. This test only parses the properties file; it never opens a
 * network connection.
 */
class ServiceBusConfigurationTest {

    private Properties loadMainApplicationProperties() throws IOException {
        Path propertiesPath = Path.of("src", "main", "resources", "application.properties");
        Properties properties = new Properties();
        try (InputStream in = Files.newInputStream(propertiesPath)) {
            properties.load(in);
        }
        return properties;
    }

    @Test
    void noRabbitMqConfigurationRemains() throws IOException {
        Properties properties = loadMainApplicationProperties();

        properties.stringPropertyNames().forEach(name ->
                assertFalse(name.toLowerCase().contains("rabbitmq"),
                        "no spring.rabbitmq.* property should remain: " + name));
    }

    @Test
    void noConnectionStringOrSecretIsConfigured() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertNull(properties.getProperty("spring.cloud.azure.servicebus.connection-string"),
                "no connection string should be stored in application configuration");
        properties.stringPropertyNames().stream()
                .filter(name -> name.toLowerCase().contains("servicebus") || name.toLowerCase().contains("jms"))
                .forEach(name ->
                        assertFalse(name.toLowerCase().contains("password") || name.toLowerCase().contains("secret")
                                        || name.toLowerCase().contains("connection-string"),
                                "no password/secret/connection-string property should be configured for messaging: " + name));
    }

    @Test
    void managedIdentityAuthenticationIsEnabledForServiceBus() throws IOException {
        Properties properties = loadMainApplicationProperties();

        assertEquals("true", properties.getProperty("spring.cloud.azure.credential.managed-identity-enabled"),
                "managed identity authentication must be enabled for Service Bus");
    }

    @Test
    void serviceBusNamespaceIsExternalizedNotHardcoded() throws IOException {
        Properties properties = loadMainApplicationProperties();

        String namespace = properties.getProperty("spring.cloud.azure.servicebus.namespace");
        assertTrue(namespace != null && namespace.startsWith("${") && namespace.endsWith("}"),
                "the Service Bus namespace must be supplied via environment configuration, not hardcoded");
    }
}
