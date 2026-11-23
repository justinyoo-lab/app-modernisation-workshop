package com.microsoft.migration.assets.worker.azureit;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class AzureItReportDirectoryTest {
    @TempDir
    Path tempDir;

    @Test
    void createsDirectoryButNeverReusesAnExistingPath() throws Exception {
        Path reports = tempDir.resolve("reports");
        assertEquals(0, reserve(reports));
        Path existingReport = reports.resolve("existing.xml");
        Files.writeString(existingReport, "preserve");
        assertNotEquals(0, reserve(reports));
        assertEquals("preserve", Files.readString(existingReport));
        assertNotEquals(0, reserve(tempDir.resolve("missing-parent").resolve("reports")));
    }

    @Test
    void concurrentReservationsHaveOnlyOneWinner() throws Exception {
        Path reports = tempDir.resolve("reports");
        Process first = startReservation(reports);
        Process second = null;
        try {
            second = startReservation(reports);
            int firstExit = waitFor(first);
            int secondExit = waitFor(second);
            assertTrue((firstExit == 0) != (secondExit == 0), "Exactly one reservation must succeed");
        } finally {
            first.destroyForcibly();
            if (second != null) {
                second.destroyForcibly();
            }
        }
    }

    private int reserve(Path reports) throws Exception {
        Process process = startReservation(reports);
        try {
            return waitFor(process);
        } finally {
            process.destroyForcibly();
        }
    }

    private Process startReservation(Path reports) throws Exception {
        String executable = Path.of(System.getProperty("java.home"), "bin", "java").toString();
        Path source = Path.of("..", "scripts", "AzureItReportDirectory.java").toAbsolutePath().normalize();
        return new ProcessBuilder(executable, source.toString(), reports.toString())
            .redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
    }

    private int waitFor(Process process) throws Exception {
        if (!process.waitFor(30, TimeUnit.SECONDS)) {
            process.destroyForcibly();
            fail("Report directory helper timed out");
        }
        return process.exitValue();
    }
}
