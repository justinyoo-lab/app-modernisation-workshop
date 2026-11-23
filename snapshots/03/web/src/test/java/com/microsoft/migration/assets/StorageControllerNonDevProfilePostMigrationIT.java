package com.microsoft.migration.assets;

import com.azure.core.http.rest.PagedIterable;
import com.azure.core.http.rest.PagedResponse;
import com.azure.core.util.IterableStream;
import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobItemProperties;
import com.microsoft.migration.assets.model.ImageMetadata;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.messaging.Message;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.io.InputStream;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.microsoft.migration.assets.PostMigrationTestFixtures.SeedRow;

import static com.microsoft.migration.assets.PostMigrationTestFixtures.readFixture;
import static com.microsoft.migration.assets.PostMigrationTestFixtures.readSeedRows;
import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.flash;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Post-migration integration tests (Phase 3, {@code verify-test-baseline}) for the {@code web}
 * module's HTTP entry points while a non-{@code dev} Spring profile is active (no profile is
 * activated here: {@code AzureBlobService} is {@code @Profile("!dev")}, so the default profile
 * already satisfies it), routing through
 * {@link com.microsoft.migration.assets.service.AzureBlobService}. Generated 1:1 from
 * {@code web/src/test/test-cases/test-cases.md}, covering every non-dev-profile {@code TC-WEB-*}
 * case.
 * <p>
 * Per {@code infra-decision-table.md}, every external dependency is {@code mock}: the full Spring
 * application context is booted, but {@link BlobContainerClient}, {@link ServiceBusTemplate} and
 * {@link ImageMetadataRepository} are replaced with Mockito mocks at the SDK/repository boundary
 * so no real Azure Blob Storage, Service Bus, or PostgreSQL resource is ever contacted.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
class StorageControllerNonDevProfilePostMigrationIT {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private BlobContainerClient blobContainerClient;

    @MockitoBean
    private ServiceBusTemplate serviceBusTemplate;

    @MockitoBean
    private ImageMetadataRepository imageMetadataRepository;

    @SuppressWarnings("unchecked")
    private static PagedIterable<BlobItem> pagedIterableOf(BlobItem... items) {
        PagedResponse<BlobItem> response = mock(PagedResponse.class);
        when(response.getElements()).thenReturn(IterableStream.of(List.of(items)));
        when(response.getContinuationToken()).thenReturn(null);
        return new PagedIterable<>(() -> response);
    }

    private static BlobItem blobItem(String name, long size, OffsetDateTime lastModified) {
        BlobItemProperties properties = new BlobItemProperties()
                .setLastModified(lastModified)
                .setContentLength(size);
        return new BlobItem().setName(name).setProperties(properties);
    }

    private static ImageMetadata toMetadata(SeedRow row) {
        ImageMetadata metadata = new ImageMetadata();
        metadata.setId(row.id());
        metadata.setFilename(row.filename());
        metadata.setContentType(row.contentType());
        metadata.setSize(row.size());
        metadata.setS3Key(row.s3Key());
        metadata.setS3Url(row.s3Url());
        metadata.setThumbnailKey(row.thumbnailKey());
        metadata.setThumbnailUrl(row.thumbnailUrl());
        metadata.setUploadedAt(LocalDateTime.now().minusDays(1));
        metadata.setLastModified(LocalDateTime.now().minusDays(1));
        return metadata;
    }

    // --- TC-WEB-002: Upload image — happy path (non-dev / S3 storage profile) --------------

    @Test
    void tcWeb002_uploadNonDevHappyPath() throws Exception {
        byte[] sampleBytes = readFixture("inputs/sample.jpg");
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient);
        AtomicReference<byte[]> uploadedBytes = new AtomicReference<>();
        doAnswer(invocation -> {
            InputStream in = invocation.getArgument(0);
            uploadedBytes.set(in.readAllBytes());
            return null;
        }).when(blobClient).upload(any(InputStream.class), anyLong(), eq(true));

        MockMultipartFile file = new MockMultipartFile("file", "sample.jpg", "image/jpeg", sampleBytes);

        mockMvc.perform(multipart("/storage/upload").file(file))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("success", "File uploaded successfully"));

        ArgumentCaptor<String> keyCaptor = ArgumentCaptor.forClass(String.class);
        verify(blobContainerClient, times(1)).getBlobClient(keyCaptor.capture());
        String generatedKey = keyCaptor.getValue();
        assertTrue(generatedKey.endsWith("-sample.jpg"), "generated key must be <uuid>-sample.jpg: " + generatedKey);

        // Resource verification: byte-identical blob content.
        assertArrayEquals(sampleBytes, uploadedBytes.get());

        ArgumentCaptor<BlobHttpHeaders> headersCaptor = ArgumentCaptor.forClass(BlobHttpHeaders.class);
        verify(blobClient, times(1)).setHttpHeaders(headersCaptor.capture());
        assertEquals("image/jpeg", headersCaptor.getValue().getContentType());

        ArgumentCaptor<Message<ImageProcessingMessage>> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), messageCaptor.capture());
        ImageProcessingMessage payload = messageCaptor.getValue().getPayload();
        assertEquals(generatedKey, payload.getKey());
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals(2135L, payload.getSize());

        ArgumentCaptor<ImageMetadata> metadataCaptor = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).save(metadataCaptor.capture());
        ImageMetadata saved = metadataCaptor.getValue();
        assertEquals("sample.jpg", saved.getFilename());
        assertEquals("image/jpeg", saved.getContentType());
        assertEquals(2135L, saved.getSize());
        assertEquals(generatedKey, saved.getS3Key());

        // Negative verification: exactly one row created (already asserted via times(1) above).
        verify(imageMetadataRepository, times(1)).save(any());
    }

    // --- TC-WEB-006: Upload image — unicode filename accepted (special-input) --------------

    @Test
    void tcWeb006_uploadUnicodeFilenameAccepted() throws Exception {
        byte[] portraitBytes = readFixture("inputs/sample-portrait.png");
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(anyString())).thenReturn(blobClient);
        AtomicReference<byte[]> uploadedBytes = new AtomicReference<>();
        doAnswer(invocation -> {
            InputStream in = invocation.getArgument(0);
            uploadedBytes.set(in.readAllBytes());
            return null;
        }).when(blobClient).upload(any(InputStream.class), anyLong(), eq(true));

        String unicodeFilename = "테스트 이미지.png";
        MockMultipartFile file = new MockMultipartFile("file", unicodeFilename, "image/png", portraitBytes);

        mockMvc.perform(multipart("/storage/upload").file(file))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("success", "File uploaded successfully"));

        ArgumentCaptor<String> keyCaptor = ArgumentCaptor.forClass(String.class);
        verify(blobContainerClient, times(1)).getBlobClient(keyCaptor.capture());
        String generatedKey = keyCaptor.getValue();
        assertTrue(generatedKey.endsWith("-" + unicodeFilename), "generated key: " + generatedKey);

        assertArrayEquals(portraitBytes, uploadedBytes.get());

        ArgumentCaptor<ImageMetadata> metadataCaptor = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).save(metadataCaptor.capture());
        ImageMetadata saved = metadataCaptor.getValue();
        assertEquals(unicodeFilename, saved.getFilename());
        assertEquals("image/png", saved.getContentType());
        assertEquals(1076L, saved.getSize());

        // Negative verification: exactly one row created.
        verify(imageMetadataRepository, times(1)).save(any());
    }

    // --- TC-WEB-009: List images — happy path (non-dev / S3 storage profile) ---------------

    @Test
    void tcWeb009_listNonDevHappyPath() throws Exception {
        List<SeedRow> seedRows = readSeedRows();
        assertEquals(3, seedRows.size());

        List<ImageMetadata> metadataRows = seedRows.stream()
                .map(StorageControllerNonDevProfilePostMigrationIT::toMetadata)
                .toList();
        when(imageMetadataRepository.findAll()).thenReturn(metadataRows);

        OffsetDateTime now = OffsetDateTime.now();
        BlobItem[] blobItems = seedRows.stream()
                .map(row -> blobItem(row.s3Key(), row.size(), now))
                .toArray(BlobItem[]::new);
        PagedIterable<BlobItem> paged = pagedIterableOf(blobItems);
        when(blobContainerClient.listBlobs()).thenReturn(paged);

        String body = mockMvc.perform(get("/storage"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        for (SeedRow row : seedRows) {
            assertTrue(body.contains("data-key=\"" + row.s3Key() + "\""), "missing data-key for " + row.s3Key());
        }
        // Count only the rendered item wrapper divs, not the bare "data-key=\"" substring: the
        // page also embeds that literal text inside an unrelated client-side JS template literal
        // (list.html's auto-refresh polling script), which would otherwise inflate the count by
        // one regardless of the actual item count.
        Matcher itemMatcher = Pattern.compile("class=\"col-md-4 mb-4\"[^>]*data-key=\"").matcher(body);
        int dataKeyCount = 0;
        while (itemMatcher.find()) {
            dataKeyCount++;
        }
        assertEquals(3, dataKeyCount);
        assertTrue(!body.contains("No images found in the S3 bucket."));
    }

    // --- TC-WEB-015: Delete image — happy path (non-dev / S3 storage profile) -------------

    @Test
    void tcWeb015_deleteNonDevHappyPath() throws Exception {
        List<SeedRow> seedRows = readSeedRows();
        List<ImageMetadata> metadataRows = seedRows.stream()
                .map(StorageControllerNonDevProfilePostMigrationIT::toMetadata)
                .toList();
        when(imageMetadataRepository.findAll()).thenReturn(metadataRows);

        SeedRow targetRow = seedRows.get(0);
        String targetKey = targetRow.s3Key();
        String thumbnailKey = targetRow.thumbnailKey();

        BlobClient originalBlobClient = mock(BlobClient.class);
        BlobClient thumbnailBlobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient(targetKey)).thenReturn(originalBlobClient);
        when(blobContainerClient.getBlobClient(thumbnailKey)).thenReturn(thumbnailBlobClient);

        mockMvc.perform(post("/storage/delete/" + targetKey))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("success", "File deleted successfully"));

        // Resource verification: both the original and thumbnail blobs were deleted.
        verify(originalBlobClient, times(1)).deleteIfExists();
        verify(thumbnailBlobClient, times(1)).deleteIfExists();

        // Resource verification + negative verification: only the matching metadata row is deleted.
        ImageMetadata expectedDeleted = metadataRows.stream()
                .filter(m -> m.getS3Key().equals(targetKey))
                .findFirst().orElseThrow();
        ArgumentCaptor<ImageMetadata> deleteCaptor = ArgumentCaptor.forClass(ImageMetadata.class);
        verify(imageMetadataRepository, times(1)).delete(deleteCaptor.capture());
        assertEquals(expectedDeleted.getId(), deleteCaptor.getValue().getId());
        assertEquals(targetKey, deleteCaptor.getValue().getS3Key());
    }
}
