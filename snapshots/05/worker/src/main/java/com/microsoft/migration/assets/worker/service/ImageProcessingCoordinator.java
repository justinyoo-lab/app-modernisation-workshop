package com.microsoft.migration.assets.worker.service;

import com.azure.storage.blob.BlobContainerClient;
import com.microsoft.migration.assets.worker.model.ImageMetadata;
import com.microsoft.migration.assets.worker.repository.ImageMetadataRepository;
import com.microsoft.migration.assets.worker.util.StorageUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Profile("!dev")
@RequiredArgsConstructor
public class ImageProcessingCoordinator {
    private final ImageMetadataRepository metadataRepository;
    private final BlobContainerClient blobContainerClient;

    @Transactional(rollbackFor = Exception.class)
    public void process(String key, AbstractFileProcessingService.ProcessingAction action) throws Exception {
        ImageMetadata metadata = metadataRepository.findFirstByS3Key(key)
                .orElseThrow(() -> new IllegalStateException("Metadata not found for blob: " + key));
        String thumbnailKey = StorageUtil.getThumbnailKey(key);
        if (thumbnailKey.equals(metadata.getThumbnailKey())
                && ("/storage/view/" + thumbnailKey).equals(metadata.getThumbnailUrl())
                && blobContainerClient.getBlobClient(thumbnailKey).exists()) {
            return;
        }
        action.run();
    }
}
