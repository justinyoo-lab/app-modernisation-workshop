package com.microsoft.migration.assets.service;

import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.Locale;
import java.util.Set;

/**
 * Restricts uploads accepted by {@link StorageService#uploadObject(MultipartFile)} to a small
 * allowlist of image types.
 * <p>
 * Without this check, any {@link MultipartFile} - regardless of extension or declared
 * {@code Content-Type} - is persisted to storage and then automatically handed to
 * {@code AbstractFileProcessingService#generateThumbnail} in the worker module, which reads it
 * with {@code ImageIO.read} and writes a derived thumbnail. Accepting arbitrary file types here
 * (e.g. executables, scripts, or other dangerous content masquerading as an upload) is an
 * unrestricted-upload-of-dangerous-file-type weakness (CWE-434). Validating both the filename
 * extension and the declared MIME type against an allowlist closes that gap before the file is
 * ever written to blob storage or queued for processing.
 */
final class UploadedFileValidator {

    private static final Set<String> ALLOWED_EXTENSIONS = Set.of(
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"
    );

    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
            "image/jpeg", "image/png", "image/gif", "image/bmp", "image/webp", "image/x-ms-bmp"
    );

    private UploadedFileValidator() {
    }

    /**
     * Validates that the given upload is a non-blank, allowlisted image file, throwing
     * {@link IOException} otherwise.
     */
    static void validate(MultipartFile file) throws IOException {
        String filename = file.getOriginalFilename();
        if (!StringUtils.hasText(filename)) {
            throw new IOException("Uploaded file must have a filename");
        }

        String extension = extensionOf(filename);
        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new IOException("Unsupported file type: only image uploads (" + ALLOWED_EXTENSIONS
                    + ") are allowed");
        }

        String contentType = file.getContentType();
        if (contentType == null || !ALLOWED_CONTENT_TYPES.contains(contentType.toLowerCase(Locale.ROOT))) {
            throw new IOException("Unsupported content type: only image uploads are allowed");
        }
    }

    private static String extensionOf(String filename) {
        int dotIndex = filename.lastIndexOf('.');
        return dotIndex >= 0 ? filename.substring(dotIndex).toLowerCase(Locale.ROOT) : "";
    }
}
