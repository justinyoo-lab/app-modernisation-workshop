package com.microsoft.migration.assets.repository;

import com.microsoft.migration.assets.model.ImageMetadata;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase.Replace;

/**
 * Repository-facing behavior tests for {@link ImageMetadataRepository}.
 *
 * These tests run against an in-memory, embedded database only (see
 * src/test/resources/application.properties) and never connect to a live
 * Azure Database for PostgreSQL instance. They verify that CRUD operations
 * and S3-path metadata fields continue to behave exactly as before the
 * managed-identity datasource migration.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.ANY)
class ImageMetadataRepositoryTest {

    @Autowired
    private ImageMetadataRepository repository;

    private ImageMetadata newMetadata(String id) {
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId(id);
        metadata.setFilename("sample.jpg");
        metadata.setContentType("image/jpeg");
        metadata.setSize(2048L);
        metadata.setS3Key("uploads/" + id + "/sample.jpg");
        metadata.setS3Url("https://bucket.s3.amazonaws.com/uploads/" + id + "/sample.jpg");
        metadata.setThumbnailKey("uploads/" + id + "/sample_thumbnail.jpg");
        metadata.setThumbnailUrl("https://bucket.s3.amazonaws.com/uploads/" + id + "/sample_thumbnail.jpg");
        return metadata;
    }

    @Test
    void savesAndRetrievesEntityPreservingS3PathMetadata() {
        String id = UUID.randomUUID().toString();
        ImageMetadata saved = repository.save(newMetadata(id));

        Optional<ImageMetadata> found = repository.findById(id);

        assertThat(found).isPresent();
        ImageMetadata result = found.get();
        assertThat(result.getFilename()).isEqualTo("sample.jpg");
        assertThat(result.getContentType()).isEqualTo("image/jpeg");
        assertThat(result.getSize()).isEqualTo(2048L);
        assertThat(result.getS3Key()).isEqualTo(saved.getS3Key());
        assertThat(result.getS3Url()).isEqualTo(saved.getS3Url());
        assertThat(result.getThumbnailKey()).isEqualTo(saved.getThumbnailKey());
        assertThat(result.getThumbnailUrl()).isEqualTo(saved.getThumbnailUrl());
        assertThat(result.getUploadedAt()).isNotNull();
        assertThat(result.getLastModified()).isNotNull();
    }

    @Test
    void updatingEntityRefreshesLastModifiedButKeepsUploadedAt() throws InterruptedException {
        String id = UUID.randomUUID().toString();
        ImageMetadata saved = repository.saveAndFlush(newMetadata(id));
        LocalDateTime originalUploadedAt = saved.getUploadedAt();
        LocalDateTime originalLastModified = saved.getLastModified();

        Thread.sleep(5);
        saved.setThumbnailKey("uploads/" + id + "/regenerated_thumbnail.jpg");
        ImageMetadata updated = repository.saveAndFlush(saved);

        assertThat(updated.getUploadedAt()).isEqualTo(originalUploadedAt);
        assertThat(updated.getLastModified()).isAfterOrEqualTo(originalLastModified);
        assertThat(updated.getThumbnailKey()).isEqualTo("uploads/" + id + "/regenerated_thumbnail.jpg");
    }

    @Test
    void findAllAndDeleteBehaveLikeStandardJpaRepository() {
        String id = UUID.randomUUID().toString();
        repository.save(newMetadata(id));

        List<ImageMetadata> all = repository.findAll();
        assertThat(all).extracting(ImageMetadata::getId).contains(id);

        repository.deleteById(id);

        assertThat(repository.findById(id)).isEmpty();
    }
}
