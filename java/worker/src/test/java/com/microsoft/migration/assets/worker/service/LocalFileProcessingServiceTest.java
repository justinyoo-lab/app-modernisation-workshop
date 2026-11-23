package com.microsoft.migration.assets.worker.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LocalFileProcessingServiceTest {
    @TempDir
    Path tempDir;

    @Test
    void generatesThumbnailFromOpaquePng() throws Exception {
        BufferedImage image = new BufferedImage(100, 100, BufferedImage.TYPE_3BYTE_BGR);
        image.setRGB(50, 50, 0xffff0000);
        Path original = tempDir.resolve("opaque.png");
        Path thumbnail = tempDir.resolve("opaque-thumbnail.png");
        assertTrue(ImageIO.write(image, "png", original.toFile()));

        new LocalFileProcessingService().generateThumbnail(original, thumbnail);

        BufferedImage result = ImageIO.read(thumbnail.toFile());
        assertEquals(100, result.getWidth());
        assertEquals(100, result.getHeight());
        assertEquals(0xffff0000, result.getRGB(50, 50));
    }

    @Test
    void generatesThumbnailFromTransparentPng() throws Exception {
        BufferedImage image = new BufferedImage(100, 100, BufferedImage.TYPE_4BYTE_ABGR);
        image.setRGB(50, 50, 0x80ff0000);
        Path original = tempDir.resolve("original.png");
        Path thumbnail = tempDir.resolve("thumbnail.png");
        assertTrue(ImageIO.write(image, "png", original.toFile()));

        new LocalFileProcessingService().generateThumbnail(original, thumbnail);

        BufferedImage result = ImageIO.read(thumbnail.toFile());
        assertEquals(100, result.getWidth());
        assertEquals(100, result.getHeight());
        assertTrue(result.getColorModel().hasAlpha());
    }
}
