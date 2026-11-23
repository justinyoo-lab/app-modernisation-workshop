package com.microsoft.migration.assets;

import com.azure.spring.messaging.servicebus.core.ServiceBusTemplate;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.microsoft.migration.assets.repository.ImageMetadataRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import java.io.InputStream;
import java.util.concurrent.atomic.AtomicReference;

import static com.microsoft.migration.assets.PostMigrationTestFixtures.readFixture;
import static com.microsoft.migration.assets.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Post-migration integration tests (Phase 3, {@code verify-test-baseline}) for the two {@code dev}
 * profile upload failure cases (TC-WEB-004, TC-WEB-007) that require a genuine, container-driven
 * HTTP round trip rather than {@code MockMvc}'s mock dispatch.
 * <p>
 * Both cases need Spring Boot's real, uncaught-exception-to-error-page handling: TC-WEB-004's
 * {@code MaxUploadSizeExceededException} is only ever raised by the servlet container's real
 * multipart/parts parsing (Tomcat), which {@code MockMvc}'s {@code multipart(...)} request builder
 * bypasses entirely (it constructs an already-parsed {@code MockMultipartHttpServletRequest}, so
 * {@code spring.servlet.multipart.max-file-size} is never enforced and the request reaches
 * {@code S3Controller.uploadObject} unconditionally). TC-WEB-007's uncaught broker-connectivity
 * {@code RuntimeException} similarly needs the real embedded server's error dispatch (via the
 * servlet container's error page mechanism) to produce a genuine HTTP response status rather than
 * being rethrown directly out of {@code MockMvc.perform(...)}.
 * <p>
 * This is a deliberate, narrowly-scoped split from {@link StorageControllerDevProfilePostMigrationIT}
 * (which keeps every other dev-profile case on {@code MockMvc} + {@code WebEnvironment.MOCK}):
 * combining {@code @AutoConfigureMockMvc} with {@code WebEnvironment.RANDOM_PORT} in one class
 * makes {@code MockMvc} itself issue real over-the-wire HTTP requests handled on separate Tomcat
 * worker threads, which was empirically observed to corrupt Mockito's per-thread "ongoing
 * stubbing" state for the list/view-page tests' ad-hoc {@code PagedIterable}/{@code BlobItem}
 * mocks (manifesting as spurious {@code UnfinishedStubbingException}s unrelated to this class's
 * own two cases). Isolating the real-server cases here keeps both groups reliable.
 * <p>
 * Per {@code infra-decision-table.md}, every external dependency is still {@code mock}:
 * {@link BlobContainerClient}, {@link ServiceBusTemplate} and {@link ImageMetadataRepository} are
 * Mockito mocks; only the HTTP transport itself is real.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureTestRestTemplate
@ActiveProfiles("dev")
class StorageControllerDevProfileRealServerPostMigrationIT {

    @Autowired
    private TestRestTemplate restTemplate;

    @MockitoBean
    private BlobContainerClient blobContainerClient;

    @MockitoBean
    private ServiceBusTemplate serviceBusTemplate;

    @MockitoBean
    private ImageMetadataRepository imageMetadataRepository;

    private ResponseEntity<String> postMultipart(String filename, byte[] content) {
        ByteArrayResource resource = new ByteArrayResource(content) {
            @Override
            public String getFilename() {
                return filename;
            }
        };
        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        HttpHeaders partHeaders = new HttpHeaders();
        partHeaders.setContentType(MediaType.IMAGE_JPEG);
        body.add("file", new HttpEntity<>(resource, partHeaders));

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);
        HttpEntity<MultiValueMap<String, Object>> request = new HttpEntity<>(body, headers);
        return restTemplate.postForEntity("/storage/upload", request, String.class);
    }

    // --- TC-WEB-004: Upload image — file exceeds configured maximum size (boundary) --------

    /**
     * Spring Framework 6.1+ (bundled with this Spring Boot 4 migration) added built-in handling
     * that maps an uncaught {@code MaxUploadSizeExceededException} to {@code 413 Payload Too Large}
     * via {@code DefaultHandlerExceptionResolver}, instead of the pre-migration {@code 500 Internal
     * Server Error}. This is an approved framework-upgrade behavior change (task 002), not an app
     * bug; the frozen spec (test-cases.md TC-WEB-004) has been re-frozen to expect {@code 413}.
     */
    @Test
    void tcWeb004_uploadExceedsMaxSize() throws Exception {
        byte[] oversized = readFixture("inputs/oversized-10mb-plus.bin");
        assertEquals(10_486_784, oversized.length);

        ResponseEntity<String> response = postMultipart("oversized.jpg", oversized);

        assertEquals(HttpStatus.CONTENT_TOO_LARGE, response.getStatusCode());
        verify(blobContainerClient, never()).getBlobClient(any());
        verify(serviceBusTemplate, never()).send(any(), any());
    }

    // --- TC-WEB-007: Upload image — downstream queue unavailable (failure, dev profile) ----

    @Test
    void tcWeb007_uploadQueueUnavailable() throws Exception {
        byte[] tinyBytes = readFixture("inputs/tiny.jpg");
        BlobClient blobClient = mock(BlobClient.class);
        when(blobContainerClient.getBlobClient("tiny.jpg")).thenReturn(blobClient);
        AtomicReference<byte[]> uploadedBytes = new AtomicReference<>();
        doAnswer(invocation -> {
            InputStream in = invocation.getArgument(0);
            uploadedBytes.set(in.readAllBytes());
            return null;
        }).when(blobClient).upload(any(InputStream.class), anyLong(), eq(true));
        doThrow(new RuntimeException("Connection refused: broker unavailable"))
                .when(serviceBusTemplate).send(eq(IMAGE_PROCESSING_QUEUE), any());

        ResponseEntity<String> response = postMultipart("tiny.jpg", tinyBytes);

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, response.getStatusCode());

        // Resource verification: write-before-publish ordering means the file write persists.
        assertArrayEquals(tinyBytes, uploadedBytes.get());

        // Negative verification: the publish attempt was made but failed (nothing was enqueued),
        // and dev/local never writes image_metadata regardless of outcome.
        verify(serviceBusTemplate, times(1)).send(eq(IMAGE_PROCESSING_QUEUE), any());
        verify(imageMetadataRepository, never()).save(any());
    }
}
