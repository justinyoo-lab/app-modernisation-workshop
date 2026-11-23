import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

class AzureItReportDirectory {
    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            throw new IllegalArgumentException("Expected one report directory path");
        }
        Files.createDirectory(Path.of(args[0]));
    }
}
