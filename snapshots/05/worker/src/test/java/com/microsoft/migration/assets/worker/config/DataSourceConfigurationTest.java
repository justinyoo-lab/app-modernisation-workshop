package com.microsoft.migration.assets.worker.config;

import com.azure.identity.DefaultAzureCredential;
import com.azure.identity.ManagedIdentityCredential;
import com.azure.identity.extensions.implementation.credential.TokenCredentialProviderOptions;
import com.azure.identity.extensions.implementation.credential.provider.TokenCredentialProvider;
import com.azure.spring.cloud.autoconfigure.implementation.context.properties.AzureGlobalProperties;
import com.azure.spring.cloud.autoconfigure.implementation.passwordless.properties.AzureJdbcPasswordlessProperties;
import com.azure.spring.cloud.core.implementation.credential.resolver.AzureTokenCredentialResolver;
import com.azure.spring.cloud.core.implementation.factory.credential.DefaultAzureCredentialBuilderFactory;
import com.azure.spring.cloud.core.implementation.util.AzurePasswordlessPropertiesUtils;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.mock.env.MockEnvironment;

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
 * Verifies that the production datasource configuration for the worker module
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
        assertTrue(url.contains("sslmode=verify-full"), "datasource URL must verify the server certificate and hostname");
        assertTrue(url.contains("sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory"),
                "datasource URL must use the Java truststore");
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
    void localProfileSelectsDefaultCredentialAndHigherPriorityConfigurationWins() throws IOException {
        Properties local = new Properties();
        try (InputStream in = Files.newInputStream(Path.of("src", "main", "resources", "application-local.properties"))) {
            local.load(in);
        }
        MockEnvironment environment = new MockEnvironment();
        environment.getPropertySources().addLast(new PropertiesPropertySource("local", local));
        environment.getPropertySources().addLast(new PropertiesPropertySource("main", loadMainApplicationProperties()));
        AzureTokenCredentialResolver resolver = new AzureTokenCredentialResolver();

        AzureGlobalProperties localProperties = Binder.get(environment)
                .bind("spring.cloud.azure", Bindable.of(AzureGlobalProperties.class)).get();
        assertNull(resolver.resolve(localProperties));
        assertTrue(new DefaultAzureCredentialBuilderFactory(localProperties).build().build()
                instanceof DefaultAzureCredential);
        assertTrue(databaseCredential(localProperties) instanceof DefaultAzureCredential);

        environment.setProperty("spring.cloud.azure.credential.managed-identity-enabled", "true");
        AzureGlobalProperties overrideProperties = Binder.get(environment)
                .bind("spring.cloud.azure", Bindable.of(AzureGlobalProperties.class)).get();
        assertTrue(resolver.resolve(overrideProperties) instanceof ManagedIdentityCredential);
        assertTrue(databaseCredential(overrideProperties) instanceof ManagedIdentityCredential);
    }

    private Object databaseCredential(AzureGlobalProperties global) {
        AzureJdbcPasswordlessProperties merged = new AzureJdbcPasswordlessProperties();
        AzurePasswordlessPropertiesUtils.mergeAzureCommonProperties(global, new AzureJdbcPasswordlessProperties(), merged);
        TokenCredentialProviderOptions options = new TokenCredentialProviderOptions(merged.toPasswordlessProperties());
        return TokenCredentialProvider.createDefault(options).get();
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
