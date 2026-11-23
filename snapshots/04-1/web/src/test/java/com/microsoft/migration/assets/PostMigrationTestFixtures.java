package com.microsoft.migration.assets;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Shared, read-only helpers used by the {@code *PostMigrationIT} test classes (Phase 3,
 * {@code verify-test-baseline}) to load the frozen fixtures under
 * {@code web/src/test/test-cases/testdata/} without fabricating any byte content. Paths are
 * resolved relative to the {@code web} module root, matching the convention already used by
 * {@code BlobStorageConfigurationTest}/{@code ServiceBusConfigurationTest}.
 */
final class PostMigrationTestFixtures {

    static final Path TESTDATA = Path.of("src", "test", "test-cases", "testdata");

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private PostMigrationTestFixtures() {
    }

    static byte[] readFixture(String relativePathUnderTestdata) throws IOException {
        return Files.readAllBytes(TESTDATA.resolve(relativePathUnderTestdata));
    }

    /** One row of {@code testdata/seed-data/image-metadata-seed.json}. */
    record SeedRow(String id, String filename, String contentType, long size, String s3Key, String s3Url,
                   String thumbnailKey, String thumbnailUrl) {
    }

    static List<SeedRow> readSeedRows() throws IOException {
        Path seedPath = TESTDATA.resolve("seed-data/image-metadata-seed.json");
        SeedRow[] rows = MAPPER.readValue(seedPath.toFile(), SeedRow[].class);
        return List.of(rows);
    }
}
