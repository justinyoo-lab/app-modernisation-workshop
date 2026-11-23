package com.microsoft.migration.assets.repository;

import com.microsoft.migration.assets.model.ImageProcessingOutbox;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.time.Instant;
import java.util.List;

public interface ImageProcessingOutboxRepository extends JpaRepository<ImageProcessingOutbox, String> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    List<ImageProcessingOutbox> findTop50ByNextAttemptAtLessThanEqualOrderByCreatedAtAsc(Instant now);
}
