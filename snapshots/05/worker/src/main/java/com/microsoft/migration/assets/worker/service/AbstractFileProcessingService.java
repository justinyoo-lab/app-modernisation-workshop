package com.microsoft.migration.assets.worker.service;

import com.azure.messaging.servicebus.ServiceBusReceivedMessageContext;
import com.azure.spring.messaging.servicebus.implementation.core.annotation.ServiceBusListener;
import com.azure.spring.messaging.servicebus.support.ServiceBusMessageHeaders;
import com.microsoft.migration.assets.worker.model.ImageProcessingMessage;
import com.microsoft.migration.assets.worker.util.StorageUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.handler.annotation.Header;

import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static com.microsoft.migration.assets.worker.config.ServiceBusConfig.IMAGE_PROCESSING_QUEUE;

@Slf4j
public abstract class AbstractFileProcessingService implements FileProcessor {

    @ServiceBusListener(destination = IMAGE_PROCESSING_QUEUE)
    public void processImage(final ImageProcessingMessage message,
                           @Header(ServiceBusMessageHeaders.RECEIVED_MESSAGE_CONTEXT) ServiceBusReceivedMessageContext context) {
        boolean processingSuccess = false;
        Path tempDir = null;
        Path originalFile = null;
        Path thumbnailFile = null;

        try {
            log.info("Processing image: {}", message.getKey());

            tempDir = Files.createTempDirectory("image-processing");
            originalFile = tempDir.resolve("original" + StorageUtil.getExtension(message.getKey()));
            thumbnailFile = tempDir.resolve("thumbnail" + StorageUtil.getExtension(message.getKey()));

            // Only process if message matches our storage type
            if (matchesStorageType(message.getStorageType())) {
                Path input = originalFile;
                Path output = thumbnailFile;
                processWithCoordination(message, () -> {
                    downloadOriginal(message.getKey(), input);
                    generateThumbnail(input, output);
                    String thumbnailKey = StorageUtil.getThumbnailKey(message.getKey());
                    uploadThumbnail(output, thumbnailKey, message.getContentType());
                });

                log.info("Successfully processed image: {}", message.getKey());

                // Mark processing as successful
                processingSuccess = true;
            } else {
                log.error("Unsupported message storage type: {} (we handle {})",
                    message.getStorageType(), getStorageType());
            }
        } catch (Exception e) {
            log.error("Failed to process image: " + message.getKey(), e);
        } finally {
            cleanup(originalFile);
            cleanup(thumbnailFile);
            cleanup(tempDir);
            try {
                if (context != null) {
                    if (processingSuccess) {
                        // Acknowledge (complete) the message if processing was successful
                        context.complete();
                        log.debug("Message acknowledged for: {}", message.getKey());
                    } else {
                        context.deadLetter();
                        log.debug("Message dead-lettered for: {}", message.getKey());
                    }
                } else {
                    log.error("No Service Bus context to settle message {}", message.getKey());
                }
            } catch (Exception e) {
                log.error("Error handling Service Bus acknowledgment for: {}", message.getKey(), e);
            }

        }
    }

    private void cleanup(Path path) {
        if (path == null) {
            return;
        }

        try {
            Files.deleteIfExists(path);
        } catch (IOException | SecurityException e) {
            log.error("Failed to remove temporary path {}", path, e);
        }
    }

    @FunctionalInterface
    protected interface ProcessingAction {
        void run() throws Exception;
    }

    protected void processWithCoordination(ImageProcessingMessage message, ProcessingAction action) throws Exception {
        action.run();
    }
    
    protected abstract String generateUrl(String key);

    /**
     * Returns {@code true} if the given Service Bus message's {@code storageType} should be
     * routed to this processor. Defaults to an exact match against {@link #getStorageType()};
     * overridden by {@link AzureBlobFileProcessingService} to also accept the legacy {@code "s3"}
     * literal for backward compatibility with messages produced before the Azure Blob Storage
     * migration.
     */
    protected boolean matchesStorageType(String messageStorageType) {
        return getStorageType().equals(messageStorageType);
    }

    protected void generateThumbnail(Path input, Path output) throws IOException {
        log.info("Generating thumbnail for: {}", input);

        // Read the original image
        BufferedImage originalImage = ImageIO.read(input.toFile());
        if (originalImage == null) {
            throw new IOException("Could not read image file: " + input);
        }

        int originalWidth = originalImage.getWidth();
        int originalHeight = originalImage.getHeight();

        // Calculate thumbnail dimensions while preserving aspect ratio
        // Increased size significantly for better clarity (600px max dimension)
        int maxDimension = 600;
        int thumbnailWidth, thumbnailHeight;
        
        double aspectRatio = (double) originalWidth / originalHeight;

        if (originalWidth > originalHeight) {
            thumbnailWidth = maxDimension;
            thumbnailHeight = (int) (maxDimension / aspectRatio);
        } else {
            thumbnailHeight = maxDimension;
            thumbnailWidth = (int) (maxDimension * aspectRatio);
        }

        // Extreme aspect ratios (e.g. a single-pixel-tall/wide image) can truncate one of the
        // double-derived dimensions above to zero when cast to int. A zero dimension is an
        // invalid BufferedImage/scaling argument (CWE-681: Incorrect Conversion between Numeric
        // Types; CWE-682: Incorrect Calculation), so clamp both dimensions to a minimum of 1px.
        thumbnailWidth = Math.max(thumbnailWidth, 1);
        thumbnailHeight = Math.max(thumbnailHeight, 1);

        // Multi-step scaling for higher quality
        // This progressive scaling produces better results than single-step scaling
        BufferedImage resultImage = progressiveScaling(originalImage, thumbnailWidth, thumbnailHeight);

        // Sharpen the image to enhance details
        resultImage = sharpenImage(resultImage);

        // Determine the output format based on the file extension
        String extension = StorageUtil.getExtension(output.toString());
        if (extension.startsWith(".")) {
            extension = extension.substring(1);
        }
        if (extension.isEmpty()) {
            extension = "jpg"; // Default to jpg if no extension found
        }

        // Write the thumbnail with optimized settings for different formats.
        // The ImageWriter and ImageOutputStream below are released via try-with-resources (and,
        // for the writer, a finally block, since ImageWriter does not implement Closeable) so
        // that a failure during setOutput/write/dispose cannot leak the resource (CWE-772:
        // Missing Release of Resource after Effective Lifetime).
        if (extension.equalsIgnoreCase("jpg") || extension.equalsIgnoreCase("jpeg")) {
            // For JPEG, we need to set compression quality
            javax.imageio.ImageWriter jpgWriter = javax.imageio.ImageIO.getImageWritersByFormatName("jpg").next();
            try {
                javax.imageio.ImageWriteParam jpgWriteParam = jpgWriter.getDefaultWriteParam();
                jpgWriteParam.setCompressionMode(javax.imageio.ImageWriteParam.MODE_EXPLICIT);
                // Higher compression quality (0.95 for maximum clarity)
                jpgWriteParam.setCompressionQuality(0.95f);

                javax.imageio.IIOImage outputImage = new javax.imageio.IIOImage(resultImage, null, null);
                try (javax.imageio.stream.ImageOutputStream outputStream =
                        javax.imageio.ImageIO.createImageOutputStream(output.toFile())) {
                    jpgWriter.setOutput(outputStream);
                    jpgWriter.write(null, outputImage, jpgWriteParam);
                }
            } finally {
                jpgWriter.dispose();
            }
        } else {
            // For PNG, use compression level 0 (no compression) for best quality
            javax.imageio.ImageWriteParam pngWriteParam = null;
            if (extension.equalsIgnoreCase("png")) {
                javax.imageio.ImageWriter pngWriter = ImageIO.getImageWritersByFormatName("png").next();
                try {
                    pngWriteParam = pngWriter.getDefaultWriteParam();
                    if (pngWriteParam.canWriteCompressed()) {
                        pngWriteParam.setCompressionMode(javax.imageio.ImageWriteParam.MODE_EXPLICIT);
                        pngWriteParam.setCompressionType("Deflate");
                        pngWriteParam.setCompressionQuality(0.0f); // 0 = best quality for PNG

                        javax.imageio.IIOImage outputImage = new javax.imageio.IIOImage(resultImage, null, null);
                        try (javax.imageio.stream.ImageOutputStream outputStream =
                                javax.imageio.ImageIO.createImageOutputStream(output.toFile())) {
                            pngWriter.setOutput(outputStream);
                            pngWriter.write(null, outputImage, pngWriteParam);
                        }
                    } else {
                        ImageIO.write(resultImage, extension, output.toFile());
                    }
                } finally {
                    pngWriter.dispose();
                }
            } else {
                // For other formats, use regular write method
                ImageIO.write(resultImage, extension, output.toFile());
            }
        }

        log.info("Successfully generated thumbnail: {}", output);
    }
    
    /**
     * Performs progressive scaling of the image for better quality.
     * This method gradually scales down the image in multiple steps rather than all at once.
     */
    private BufferedImage progressiveScaling(BufferedImage source, int targetWidth, int targetHeight) {
        // Current dimensions
        int currentWidth = source.getWidth();
        int currentHeight = source.getHeight();
        
        // Don't scale up images that are already smaller than target size
        if (currentWidth <= targetWidth && currentHeight <= targetHeight) {
            return source;
        }
        
        // Use a multi-step approach for higher quality
        BufferedImage result = source;
        
        // Scale down in multiple steps for better quality (not more than 50% each step)
        while (currentWidth > targetWidth * 1.5 || currentHeight > targetHeight * 1.5) {
            int newWidth = Math.max(currentWidth / 2, targetWidth);
            int newHeight = Math.max(currentHeight / 2, targetHeight);
            
            result = scaleImage(result, newWidth, newHeight);
            
            currentWidth = newWidth;
            currentHeight = newHeight;
        }
        
        // Final scaling to exact target dimensions
        if (currentWidth != targetWidth || currentHeight != targetHeight) {
            result = scaleImage(result, targetWidth, targetHeight);
        }
        
        return result;
    }
    
    /**
     * Scale an image to specific dimensions using high quality settings.
     */
    private BufferedImage scaleImage(BufferedImage source, int width, int height) {
        // Create a new BufferedImage for the result
        BufferedImage result;
        
        // Preserve transparency for images with alpha channel
        if (source.getTransparency() != BufferedImage.OPAQUE) {
            result = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        } else {
            result = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        }
        
        // Set up the rendering process with maximum quality settings
        Graphics2D g2d = result.createGraphics();
        g2d.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
        g2d.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g2d.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g2d.setRenderingHint(RenderingHints.KEY_COLOR_RENDERING, RenderingHints.VALUE_COLOR_RENDER_QUALITY);
        g2d.setRenderingHint(RenderingHints.KEY_DITHERING, RenderingHints.VALUE_DITHER_ENABLE);
        g2d.setRenderingHint(RenderingHints.KEY_ALPHA_INTERPOLATION, RenderingHints.VALUE_ALPHA_INTERPOLATION_QUALITY);
        g2d.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
        
        // Draw the scaled image
        g2d.drawImage(source, 0, 0, width, height, null);
        g2d.dispose();
        
        return result;
    }
    
    /**
     * Apply a sharpening filter to enhance image clarity
     */
    private BufferedImage sharpenImage(BufferedImage image) {
        int imageType = image.getTransparency() == BufferedImage.OPAQUE
                ? BufferedImage.TYPE_INT_RGB : BufferedImage.TYPE_INT_ARGB;
        if (image.getType() != imageType) {
            image = scaleImage(image, image.getWidth(), image.getHeight());
        }

        float[] sharpenMatrix = {
            0, -0.2f, 0,
            -0.2f, 1.8f, -0.2f,
            0, -0.2f, 0
        };
        
        java.awt.image.Kernel kernel = new java.awt.image.Kernel(3, 3, sharpenMatrix);
        java.awt.image.ConvolveOp convolveOp = new java.awt.image.ConvolveOp(
            kernel, java.awt.image.ConvolveOp.EDGE_NO_OP, null);
        
        // Create a compatible destination image to avoid potential issues with some image types
        BufferedImage output;
        if (image.getTransparency() != BufferedImage.OPAQUE) {
            output = new BufferedImage(image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_ARGB);
        } else {
            output = new BufferedImage(image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB); 
        }
        
        // Apply the filter
        return convolveOp.filter(image, output);
    }
}
