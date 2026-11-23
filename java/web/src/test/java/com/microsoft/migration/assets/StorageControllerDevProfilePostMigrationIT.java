package com.microsoft.migration.assets;

import com.azure.core.http.rest.PagedIterable;
import com.azure.core.http.rest.PagedResponse;
import com.azure.core.util.BinaryData;
import com.azure.core.util.IterableStream;
import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobItem;
import com.azure.storage.blob.models.BlobItemProperties;
import com.microsoft.migration.assets.model.ImageProcessingMessage;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.messaging.Message;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.io.InputStream;
import java.time.OffsetDateTime;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static com.microsoft.migration.assets.PostMigrationTestFixtures.readFixture;
import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.flash;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Post-migration integration tests (Phase 3, {@code verify-test-baseline}) for the {@code web}
 * module's HTTP entry points (all five in {@code S3Controller}) while the {@code dev} Spring
 * profile is active, routing through {@link com.microsoft.migration.assets.service.BlobFileStorageService}.
 * Covers every dev-profile {@code TC-WEB-*} case EXCEPT TC-WEB-004 and TC-WEB-007, which require a
 * real embedded server and live in {@link StorageControllerDevProfileRealServerPostMigrationIT}
 * instead (see that class's javadoc for why).
 * <p>
 * Per {@code infra-decision-table.md}, every external dependency is {@code mock}: the full Spring
 * application context is booted so the real MVC dispatch / multipart parsing / Thymeleaf
 * rendering / flash-attribute machinery is exercised end-to-end, but {@link BlobContainerClient},
 * {@link ServiceBusTemplate} and {@link ImageMetadataRepository} are replaced with Mockito mocks
 * at the SDK/repository boundary so no real Azure Blob Storage, Service Bus, or PostgreSQL
 * resource is ever contacted.
 * <p>
 * {@code BlobKeyValidator.sanitize} (the migrated path-traversal/absolute-path guard) and
 * {@code BlobFileStorageService.deleteObject}'s not-found path were restored (task 008 follow-up
 * remediation) to the frozen spec's exact wording for TC-WEB-005/TC-WEB-017: respectively
 * {@code IOException("Cannot store file with relative path outside current directory")} and
 * {@code FileNotFoundException("File not found: " + sanitizedKey)}.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
@ActiveProfiles("dev")
class StorageControllerDevProfilePostMigrationIT {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private BlobContainerClient blobContainerClient;

    @MockitoBean
    private ServiceBusTemplate serviceBusTemplate;

    @MockitoBean
    private ImageMetadataRepository imageMetadataRepository;

    /**
     * Counts rendered {@code <div class="col-md-4 mb-4" ... data-key="...">} list-item elements.
     * Anchored on the item wrapper's class attribute (not a bare {@code data-key="} substring
     * search) because {@code list.html} also embeds the literal text {@code data-key="} inside an
     * unrelated client-side JS template literal (the auto-refresh polling script), which would
     * otherwise inflate the count by one regardless of the actual item count.
     */
    private static int countDataKeyAttributes(String html) {
        Matcher matcher = Pattern.compile("class=\"col-md-4 mb-4\"[^>]*data-key=\"").matcher(html);
        int count = 0;
        while (matcher.find()) {
            count++;
        }
        return count;
    }

    /**
     * Builds a real, single-page {@link PagedIterable} backed by a mocked {@link PagedResponse}
     * (a plain interface — trivial and reliable to mock) rather than mocking {@code PagedIterable}
     * itself: {@code PagedIterable#stream()} is inherited from a separate internal Azure SDK base
     * class and was found to be unreliable to intercept directly via Mockito in this project's
     * JVM/agent setup, so driving it through its own public, real {@code Supplier}-based
     * constructor sidesteps that entirely.
     */
    @SuppressWarnings("unchecked")
    private static PagedIterable<BlobItem> pagedIterableOf(BlobItem... items) {
        PagedResponse<BlobItem> response = mock(PagedResponse.class);
        when(response.getElements()).thenReturn(IterableStream.of(java.util.List.of(items)));
        when(response.getContinuationToken()).thenReturn(null);
        return new PagedIterable<>(() -> response);
    }

    /** Real (not mocked) {@code BlobItem}/{@code BlobItemProperties}: both are final Azure SDK
     * model classes with public constructors and fluent setters, so there is no need to mock them. */
    private static BlobItem blobItem(String name, long size, OffsetDateTime timestamp) {
        BlobItemProperties properties = new BlobItemProperties()
                .setLastModified(timestamp)
                .setCreationTime(timestamp)
                .setContentLength(size);
        return new BlobItem().setName(name).setProperties(properties);
    }

    // --- TC-WEB-001: Upload image — happy path (dev / local storage profile) ---------------

    @Test
    void tcWeb001_uploadDevHappyPath() throws Exception {
        byte[] sampleBytes = readFixture("inputs/sample.jpg");
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("sample.jpg")).thenReturn(blobClient);
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

        // Resource verification: byte-identical file in the (mocked) storage container.
        assertArrayEquals(sampleBytes, uploadedBytes.get());

        // Resource verification: exactly one Service Bus message with the expected body.
        ArgumentCaptor<Message<ImageProcessingMessage>> captor = ArgumentCaptor.forClass(Message.class);
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), captor.capture());
        ImageProcessingMessage payload = captor.getValue().getPayload();
        assertEquals("sample.jpg", payload.getKey());
        assertEquals("image/jpeg", payload.getContentType());
        assertEquals("local", payload.getStorageType());
        assertEquals(2135L, payload.getSize());

        // Negative verification: no image_metadata row created for dev/local uploads.
        verify(imageMetadataRepository, never()).save(any());
    }

    // --- TC-WEB-003: Upload image — empty file rejected (boundary) -------------------------

    @Test
    void tcWeb003_uploadEmptyFileRejected() throws Exception {
        MockMultipartFile emptyFile = new MockMultipartFile("file", "empty.jpg", "image/jpeg", new byte[0]);

        mockMvc.perform(multipart("/storage/upload").file(emptyFile))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage/upload"))
                .andExpect(flash().attribute("error", "Please select a file to upload"));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
    }

    // --- TC-WEB-005: Upload image — path-traversal filename rejected (special-input) -------

    /**
     * Asserts the EXACT flash error message text declared by the frozen spec
     * ({@code test-cases.md}), now restored by {@code BlobKeyValidator.sanitize}.
     */
    @Test
    void tcWeb005_uploadPathTraversalFilenameRejected() throws Exception {
        byte[] tinyBytes = readFixture("inputs/tiny.jpg");
        MockMultipartFile file = new MockMultipartFile("file", "../tiny.jpg", "image/jpeg", tinyBytes);

        mockMvc.perform(multipart("/storage/upload").file(file))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage/upload"))
                .andExpect(flash().attribute("error",
                        "Failed to upload file: Cannot store file with relative path outside current directory"));

        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
    }

    // --- TC-WEB-008: List images — happy path (dev / local storage profile) ----------------

    @Test
    void tcWeb008_listDevHappyPath() throws Exception {
        OffsetDateTime now = OffsetDateTime.now();
        PagedIterable<BlobItem> paged = pagedIterableOf(
                blobItem("sample.jpg", 2135, now),
                blobItem("sample-portrait.png", 1076, now),
                blobItem("tiny.jpg", 633, now));
        when(blobContainerClient.listBlobs()).thenReturn(paged);

        String body = mockMvc.perform(get("/storage"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertTrue(body.contains("data-key=\"sample.jpg\""));
        assertTrue(body.contains("data-key=\"sample-portrait.png\""));
        assertTrue(body.contains("data-key=\"tiny.jpg\""));
        assertEquals(3, countDataKeyAttributes(body));
        assertTrue(!body.contains("No images found in the S3 bucket."));
    }

    // --- TC-WEB-010: List images — empty storage (boundary) --------------------------------

    @Test
    void tcWeb010_listEmptyStorage() throws Exception {
        PagedIterable<BlobItem> paged = pagedIterableOf();
        when(blobContainerClient.listBlobs()).thenReturn(paged);

        String body = mockMvc.perform(get("/storage"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertEquals(0, countDataKeyAttributes(body));
        assertEquals(1, countOccurrences(body, "No images found in the S3 bucket."));
    }

    private static int countOccurrences(String haystack, String needle) {
        int count = 0;
        int index = 0;
        while ((index = haystack.indexOf(needle, index)) != -1) {
            count++;
            index += needle.length();
        }
        return count;
    }

    // --- TC-WEB-011: View image page — happy path -------------------------------------------

    @Test
    void tcWeb011_viewPageHappyPath() throws Exception {
        OffsetDateTime now = OffsetDateTime.now();
        PagedIterable<BlobItem> paged = pagedIterableOf(blobItem("sample.jpg", 2135, now));
        when(blobContainerClient.listBlobs()).thenReturn(paged);

        String body = mockMvc.perform(get("/storage/view-page/sample.jpg"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertTrue(body.contains("sample.jpg"));
    }

    // --- TC-WEB-012: View image binary — happy path -----------------------------------------

    @Test
    void tcWeb012_viewBinaryHappyPath() throws Exception {
        byte[] sampleBytes = readFixture("inputs/sample.jpg");
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("sample.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(true);
        when(blobClient.downloadContent()).thenReturn(BinaryData.fromBytes(sampleBytes));

        mockMvc.perform(get("/storage/view/sample.jpg"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_OCTET_STREAM))
                .andExpect(content().bytes(sampleBytes));
    }

    // --- TC-WEB-013: View image page — key not found (failure) -----------------------------

    @Test
    void tcWeb013_viewPageNotFound() throws Exception {
        PagedIterable<BlobItem> paged = pagedIterableOf();
        when(blobContainerClient.listBlobs()).thenReturn(paged);

        mockMvc.perform(get("/storage/view-page/does-not-exist.jpg"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("error", "Image not found"));

        verify(blobContainerClient, never()).getBlobClient(any());
    }

    // --- TC-WEB-014: View image binary — key not found (failure) ---------------------------

    @Test
    void tcWeb014_viewBinaryNotFound() throws Exception {
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("does-not-exist.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);

        mockMvc.perform(get("/storage/view/does-not-exist.jpg"))
                .andExpect(status().isNotFound())
                .andExpect(content().string(""));
    }

    // --- TC-WEB-016: Delete image — happy path (dev / local storage profile) ---------------

    @Test
    void tcWeb016_deleteDevHappyPath() throws Exception {
        BlobClient blobClient = mock(BlobClient.class);
        BlobClient thumbnailBlobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("sample.jpg")).thenReturn(blobClient);
        when(blobContainerClient.getBlobClient("sample_thumbnail.jpg")).thenReturn(thumbnailBlobClient);
        when(blobClient.exists()).thenReturn(true);
        when(thumbnailBlobClient.exists()).thenReturn(true);

        mockMvc.perform(post("/storage/delete/sample.jpg"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("success", "File deleted successfully"));

        verify(blobClient, times(1)).delete();
        verify(thumbnailBlobClient, times(1)).delete();

        // Negative verification: image_metadata is never touched by the dev/local delete path.
        verifyNoInteractions(imageMetadataRepository);
    }

    // --- TC-WEB-017: Delete image — key not found (failure, dev profile) -------------------

    @Test
    void tcWeb017_deleteNotFound() throws Exception {
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("does-not-exist.jpg")).thenReturn(blobClient);
        when(blobClient.exists()).thenReturn(false);

        mockMvc.perform(post("/storage/delete/does-not-exist.jpg"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/storage"))
                .andExpect(flash().attribute("error", Matchers.allOf(
                        Matchers.startsWith("Failed to delete file: File not found: "),
                        Matchers.endsWith("does-not-exist.jpg"))));

        verify(blobClient, never()).delete();
    }
}
