package com.microsoft.migration.assets.service;

import org.springframework.util.StringUtils;

import java.io.IOException;

/**
 * Validates and normalizes the blob "keys" supplied by callers (upload filenames, the
 * {@code {key}} path variable on {@code S3Controller}, etc.) before they are used to address an
 * Azure Blob Storage object.
 * <p>
 * A blob key is just a string - Azure Blob Storage has no real directory structure - so without
 * validation a caller could request a key such as {@code ../../secret}, {@code /etc/passwd}, or
 * {@code C:\Windows\win.ini} and have it resolved as if it were a legitimate path segment. This
 * mirrors (and is replaces by a stronger version of) the single {@code filename.contains("..")}
 * check the previous local-filesystem implementation performed, addressing:
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
            throw new IOException("Cannot store file with relative path outside current directory");
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
