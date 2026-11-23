package com.microsoft.migration.assets.worker.service;

import org.springframework.util.StringUtils;

import java.io.IOException;

/**
 * Validates and normalizes the blob "keys" supplied to the worker's download/upload operations
 * before they are used to address an Azure Blob Storage object.
 * <p>
 * A blob key is just a string - Azure Blob Storage has no real directory structure - so without
 * validation a message carrying a key such as {@code ../../secret}, {@code /etc/passwd}, or
 * {@code C:\Windows\win.ini} could be resolved as if it were a legitimate path segment. This
 * addresses:
 * <ul>
 *     <li>CWE-22: Improper Limitation of a Pathname to a Restricted Directory</li>
 *     <li>CWE-23: Relative Path Traversal</li>
 *     <li>CWE-36: Absolute Path Traversal</li>
 * </ul>
 */
final class BlobKeyValidator {

    private BlobKeyValidator() {
    }

    /**
     * Returns a normalized, safe blob key, or throws {@link IOException} if the supplied key is
     * blank, contains a relative ("..") path traversal segment, or is an absolute path (Unix-style
     * leading slash, Windows drive letter, or UNC share).
     */
    static String sanitize(String rawKey) throws IOException {
        if (!StringUtils.hasText(rawKey)) {
            throw new IOException("Blob key must not be blank");
        }

        String key = StringUtils.cleanPath(rawKey.trim());

        if (!StringUtils.hasText(key)) {
            throw new IOException("Blob key must not be blank");
        }
        if (key.contains("..")) {
            throw new IOException("Cannot access blob with relative path outside the container: " + rawKey);
        }
        if (isAbsolutePath(key)) {
            throw new IOException("Cannot access blob with absolute path: " + rawKey);
        }

        return key;
    }

    private static boolean isAbsolutePath(String key) {
        if (key.startsWith("/") || key.startsWith("\\")) {
            return true;
        }
        // Windows drive-letter absolute path, e.g. "C:\foo" or "C:/foo"
        if (key.length() >= 2 && Character.isLetter(key.charAt(0)) && key.charAt(1) == ':') {
            return true;
        }
        // UNC share, e.g. "\\server\share"
        return key.startsWith("\\\\");
    }
}
