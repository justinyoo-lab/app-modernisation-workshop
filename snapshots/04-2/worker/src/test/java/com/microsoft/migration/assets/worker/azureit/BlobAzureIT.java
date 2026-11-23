package com.microsoft.migration.assets.worker.azureit;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class BlobAzureIT {
    @Test
    void storesPrivatelyAndReadsWithCliCredential() throws Exception {
        AzureItContext context = new AzureItContext();
        var container = context.container();
        assertNull(container.getProperties().getBlobPublicAccess(), "Container permits anonymous access");
        String key = "azure-it/" + UUID.randomUUID() + "/blob.txt";
        System.out.println("Azure IT retained blob: " + key);
        byte[] expected = "Azure IT isolated blob".getBytes(StandardCharsets.UTF_8);
        var blob = container.getBlobClient(key);
        blob.upload(new ByteArrayInputStream(expected), expected.length, false);
        var bytes = new ByteArrayOutputStream();
        blob.downloadStream(bytes);
        assertArrayEquals(expected, bytes.toByteArray());
        var request = HttpRequest.newBuilder(URI.create(blob.getBlobUrl())).GET().build();
        int status = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.discarding()).statusCode();
        assertTrue(status == 403 || status == 404, "Anonymous access did not return 403 or 404: " + status);
    }
}
