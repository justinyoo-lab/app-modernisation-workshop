package com.microsoft.migration.assets.worker.config;

import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.extensions.implementation.template.AzureAuthenticationTemplate;
import com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.postgresql.plugin.AuthenticationRequestType;
import org.springframework.jdbc.datasource.AbstractDataSource;
import reactor.core.publisher.Mono;

import java.lang.reflect.Constructor;
import java.sql.Connection;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PostgresqlTokenRefreshTest {
    @Test
    void newPhysicalConnectionRequestsAnotherTokenAfterExpiry() throws Exception {
        AtomicInteger requests = new AtomicInteger();
        AccessToken firstToken = new AccessToken("test-token-1", OffsetDateTime.now().plusSeconds(3));
        TokenCredential credential = context -> {
            requests.incrementAndGet();
            return Mono.just(firstToken.isExpired()
                    ? new AccessToken("test-token-2", OffsetDateTime.now().plusMinutes(1)) : firstToken);
        };
        AzureAuthenticationTemplate template = new AzureAuthenticationTemplate(
                () -> credential,
                tokenCredential -> tokenCredential.getToken(new TokenRequestContext().addScopes("https://example.test/.default")));
        Constructor<AzurePostgresqlAuthenticationPlugin> constructor =
                AzurePostgresqlAuthenticationPlugin.class.getDeclaredConstructor(AzureAuthenticationTemplate.class, Properties.class);
        constructor.setAccessible(true);
        AzurePostgresqlAuthenticationPlugin plugin = constructor.newInstance(template, new Properties());
        List<String> suppliedTokens = new ArrayList<>();
        AbstractDataSource fakeDriver = new AbstractDataSource() {
            @Override
            public Connection getConnection() throws SQLException {
                suppliedTokens.add(new String(plugin.getPassword(AuthenticationRequestType.CLEARTEXT_PASSWORD)));
                Connection connection = mock(Connection.class);
                when(connection.getAutoCommit()).thenReturn(true);
                when(connection.isValid(anyInt())).thenReturn(true);
                return connection;
            }

            @Override
            public Connection getConnection(String username, String password) throws SQLException {
                return getConnection();
            }
        };
        HikariConfig config = new HikariConfig();
        config.setDataSource(fakeDriver);
        config.setMinimumIdle(0);
        config.setMaximumPoolSize(1);
        try (HikariDataSource pool = new HikariDataSource(config)) {
            try (Connection ignored = pool.getConnection()) {
                assertEquals("test-token-1", suppliedTokens.getLast());
            }
            int previousRequests = requests.get();
            while (!firstToken.isExpired()) {
                Thread.sleep(50);
            }
            pool.getHikariPoolMXBean().softEvictConnections();
            try (Connection ignored = pool.getConnection()) {
                assertEquals("test-token-2", suppliedTokens.getLast());
                org.junit.jupiter.api.Assertions.assertTrue(requests.get() > previousRequests);
            }
        }
    }
}
