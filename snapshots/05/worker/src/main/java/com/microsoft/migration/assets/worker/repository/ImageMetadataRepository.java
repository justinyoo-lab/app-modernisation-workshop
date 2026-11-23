package com.microsoft.migration.assets.worker.repository;

import com.microsoft.migration.assets.worker.model.ImageMetadata;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ImageMetadataRepository extends JpaRepository<ImageMetadata, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<ImageMetadata> findFirstByS3Key(String s3Key);
}