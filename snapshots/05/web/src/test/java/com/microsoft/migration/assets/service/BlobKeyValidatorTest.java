package com.microsoft.migration.assets.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * Validates {@link BlobKeyValidator}'s path/key validation, which mitigates CWE-22, CWE-23 and
 * CWE-36 for the Azure Blob Storage-backed dev-profile storage path.
 */
class BlobKeyValidatorTest {

    @Test
    void acceptsSimpleFilename() throws IOException {
        assertEquals("photo.jpg", BlobKeyValidator.sanitize("photo.jpg"));
    }

    @Test
    void acceptsNestedPrefixKey() throws IOException {
        assertEquals("sub/photo.jpg", BlobKeyValidator.sanitize("sub/photo.jpg"));
    }

    @ParameterizedTest
    @ValueSource(strings = { "", "   " })
    void rejectsBlankKey(String blank) {
        assertThrows(IOException.class, () -> BlobKeyValidator.sanitize(blank));
    }

    @Test
    void rejectsNullKey() {
        assertThrows(IOException.class, () -> BlobKeyValidator.sanitize(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "../secret.txt",
            "../../etc/passwd",
            "sub/../../secret.txt",
            "..\\..\\secret.txt"
    })
    void rejectsRelativePathTraversal(String maliciousKey) {
        assertThrows(IOException.class, () -> BlobKeyValidator.sanitize(maliciousKey));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "/etc/passwd",
            "\\windows\\win.ini",
            "C:\\Windows\\win.ini",
            "C:/Windows/win.ini",
            "\\\\server\\share\\secret.txt"
    })
    void rejectsAbsolutePathTraversal(String maliciousKey) {
        assertThrows(IOException.class, () -> BlobKeyValidator.sanitize(maliciousKey));
    }
}
