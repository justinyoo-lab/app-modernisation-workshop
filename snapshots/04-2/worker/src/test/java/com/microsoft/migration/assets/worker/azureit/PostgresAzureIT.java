package com.microsoft.migration.assets.worker.azureit;

import com.azure.core.credential.TokenRequestContext;
import org.junit.jupiter.api.Test;

import java.sql.DriverManager;
import java.util.Properties;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class PostgresAzureIT {
    @Test
    void recordsAndReadsTestMetadataOverTls() throws Exception {
        AzureItContext context = new AzureItContext();
        String id = "azure-it-" + UUID.randomUUID();
        String key = id + ".png";
        System.out.println("Azure IT DB row id (may not exist on failure): " + id);
        var accessToken = context.credential.getToken(new TokenRequestContext()
            .addScopes("https://ossrdbms-aad.database.windows.net/.default")).block();
        assertNotNull(accessToken, "Azure CLI did not return a PostgreSQL token");
        Properties properties = new Properties();
        properties.setProperty("user", context.get("AZURE_IT_PG_USER"));
        properties.setProperty("password", accessToken.getToken());
        properties.setProperty("sslmode", "verify-full");
        properties.setProperty("sslfactory", "org.postgresql.ssl.DefaultJavaSSLFactory");
        String url = "jdbc:postgresql://" + context.get("AZURE_IT_PG_HOST") + ":5432/" + context.get("AZURE_IT_PG_DATABASE");
        try (var connection = DriverManager.getConnection(url, properties)) {
            try (var statement = connection.createStatement();
                 var result = statement.executeQuery("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")) {
                assertTrue(result.next());
                assertTrue(result.getBoolean(1), "PostgreSQL connection is not using TLS");
            }
            try (var insert = connection.prepareStatement(
                "INSERT INTO image_metadata (id, filename, content_type, size, s3_key) VALUES (?, ?, ?, ?, ?)")) {
                insert.setString(1, id);
                insert.setString(2, key);
                insert.setString(3, "image/png");
                insert.setLong(4, 1);
                insert.setString(5, key);
                assertEquals(1, insert.executeUpdate());
            }
            try (var select = connection.prepareStatement("SELECT filename, s3_key FROM image_metadata WHERE id = ?")) {
                select.setString(1, id);
                try (var result = select.executeQuery()) {
                    assertTrue(result.next());
                    assertEquals(key, result.getString(1));
                    assertEquals(key, result.getString(2));
                    assertFalse(result.next());
                }
            }
        } finally {
            properties.remove("password");
        }
    }
}
