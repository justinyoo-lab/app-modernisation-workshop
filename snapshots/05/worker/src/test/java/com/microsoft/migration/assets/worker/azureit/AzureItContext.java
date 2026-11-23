package com.microsoft.migration.assets.worker.azureit;

import com.azure.identity.AzureCliCredential;
import com.azure.identity.AzureCliCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobContainerClientBuilder;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

final class AzureItContext {
    private static final String[] AZD_VALUES = {
        "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP",
        "AZURE_IT_PG_HOST", "AZURE_IT_PG_DATABASE", "AZURE_IT_BLOB_ENDPOINT",
        "AZURE_IT_BLOB_CONTAINER", "AZURE_IT_SERVICEBUS_NAMESPACE", "AZURE_IT_SERVICEBUS_QUEUE",
        "AZURE_IT_APP_SERVICEBUS_NAMESPACE", "AZURE_IT_APP_SERVICEBUS_QUEUE"
    };
    final Map<String, String> values;
    final AzureCliCredential credential;

    AzureItContext() throws Exception {
        if (!"YES".equals(System.getenv("AZURE_IT_APPROVED")) || nonempty(System.getenv("CI"))) {
            throw new IllegalStateException("Azure IT requires interactive approval through the runner; CI is not allowed.");
        }
        var env = System.getenv();
        for (String name : AZD_VALUES) {
            required(env.get(name), name);
        }
        required(env.get("AZURE_IT_PG_USER"), "AZURE_IT_PG_USER");
        String type = command("az", "account", "show", "--query", "user.type", "--output", "tsv");
        String user = command("az", "account", "show", "--query", "user.name", "--output", "tsv");
        String subscription = command("az", "account", "show", "--query", "id", "--output", "tsv");
        if (!"user".equals(type) || !user.equals(env.get("AZURE_IT_PG_USER"))
            || !subscription.equalsIgnoreCase(env.get("AZURE_SUBSCRIPTION_ID"))) {
            throw new IllegalStateException("Azure CLI user or subscription does not match the approved target.");
        }
        for (String name : AZD_VALUES) {
            if (!env.get(name).equals(command("azd", "env", "get-value", name))) {
                throw new IllegalStateException("azd value changed or does not match: " + name);
            }
        }
        if (!env.get("AZURE_IT_PG_HOST").matches("(?i)[a-z0-9][a-z0-9-]*\\.postgres\\.database\\.azure\\.com")
            || !env.get("AZURE_IT_PG_DATABASE").matches("[A-Za-z0-9_-]+")) {
            throw new IllegalArgumentException("Invalid PostgreSQL host or database.");
        }
        URI endpoint = URI.create(env.get("AZURE_IT_BLOB_ENDPOINT"));
        if (!"https".equals(endpoint.getScheme()) || endpoint.getHost() == null
            || !endpoint.getHost().matches("(?i)[a-z0-9]{3,24}\\.blob\\.core\\.windows\\.net")
            || endpoint.getUserInfo() != null || endpoint.getQuery() != null || endpoint.getFragment() != null
            || !(endpoint.getPath().isEmpty() || "/".equals(endpoint.getPath())) || endpoint.getPort() != -1) {
            throw new IllegalArgumentException("Blob endpoint must be an HTTPS account endpoint without credentials or a path.");
        }
        if (!env.get("AZURE_IT_BLOB_CONTAINER").matches("[a-z0-9][a-z0-9-]{1,61}[a-z0-9]")
            || !env.get("AZURE_IT_SERVICEBUS_QUEUE").matches("[A-Za-z0-9][A-Za-z0-9._-]{0,259}")
            || !env.get("AZURE_IT_APP_SERVICEBUS_QUEUE").matches("[A-Za-z0-9][A-Za-z0-9._-]{0,259}")) {
            throw new IllegalArgumentException("Invalid container or queue name.");
        }
        if (namespace(env.get("AZURE_IT_SERVICEBUS_NAMESPACE")).equals(namespace(env.get("AZURE_IT_APP_SERVICEBUS_NAMESPACE")))
            && env.get("AZURE_IT_SERVICEBUS_QUEUE").equalsIgnoreCase(env.get("AZURE_IT_APP_SERVICEBUS_QUEUE"))) {
            throw new IllegalArgumentException("The test queue must not be the app queue.");
        }
        this.values = env;
        this.credential = new AzureCliCredentialBuilder().build();
    }

    String get(String key) {
        return values.get(key);
    }

    BlobContainerClient container() {
        return new BlobContainerClientBuilder().endpoint(get("AZURE_IT_BLOB_ENDPOINT"))
            .containerName(get("AZURE_IT_BLOB_CONTAINER")).credential(credential).buildClient();
    }

    String namespace() {
        return namespace(get("AZURE_IT_SERVICEBUS_NAMESPACE"));
    }

    private static String namespace(String value) {
        String result = value.toLowerCase(Locale.ROOT);
        if (!result.endsWith(".servicebus.windows.net")) {
            result += ".servicebus.windows.net";
        }
        if (!Pattern.matches("[a-z0-9][a-z0-9-]{4,48}[a-z0-9]\\.servicebus\\.windows\\.net", result)) {
            throw new IllegalArgumentException("Invalid Service Bus namespace.");
        }
        return result;
    }

    private static boolean nonempty(String value) {
        return value != null && !value.isBlank();
    }

    private static void required(String value, String name) {
        if (!nonempty(value) || !value.equals(value.trim()) || value.matches("<.*>") || value.contains("\n") || value.contains("\r")) {
            throw new IllegalArgumentException("Missing or invalid target: " + name);
        }
    }

    private static String command(String... args) throws IOException, InterruptedException {
        String[] executable = args;
        if (System.getProperty("os.name").toLowerCase(Locale.ROOT).contains("windows")) {
            executable = new String[args.length + 3];
            executable[0] = "cmd.exe";
            executable[1] = "/d";
            executable[2] = "/c";
            System.arraycopy(args, 0, executable, 3, args.length);
        }
        Process process = new ProcessBuilder(executable).redirectError(ProcessBuilder.Redirect.DISCARD).start();
        String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8).trim();
        if (process.waitFor() != 0 || output.isBlank() || output.contains("\n") || output.contains("\r")) {
            throw new IllegalStateException("Could not verify the Azure CLI or azd context.");
        }
        return output;
    }
}
