package com.microsoft.migration.assets.repository;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;

import javax.sql.DataSource;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@DataJpaTest
class DatabaseSchemaTest {
    @Autowired private DataSource dataSource;

    @Test
    void initializationTablesMatchJpaColumnsAndTypes() throws Exception {
        String script = Files.readString(Path.of("..", "infra", "database", "init.sql"));
        try (Connection expected = dataSource.getConnection();
             Connection initialized = DriverManager.getConnection("jdbc:h2:mem:init_schema_test;MODE=PostgreSQL", "sa", "")) {
            for (String table : new String[] {"image_metadata", "image_processing_outbox"}) {
                Matcher ddl = Pattern.compile("(?is)CREATE TABLE IF NOT EXISTS " + table + "\\s*\\(.*?\\);").matcher(script);
                assertTrue(ddl.find(), "missing initialization table " + table);
                initialized.createStatement().execute(ddl.group());
                assertEquals(columns(expected, table), columns(initialized, table), table);
            }
        }
    }

    private Map<String, Integer> columns(Connection connection, String table) throws Exception {
        Map<String, Integer> result = new HashMap<>();
        try (ResultSet columns = connection.getMetaData().getColumns(null, null, table.toUpperCase(), null)) {
            while (columns.next()) {
                result.put(columns.getString("COLUMN_NAME"), columns.getInt("DATA_TYPE"));
            }
        }
        return result;
    }
}
