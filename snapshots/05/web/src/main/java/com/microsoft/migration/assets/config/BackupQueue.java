package com.microsoft.migration.assets.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("backup")
public class BackupQueue {
    private final String name;

    public BackupQueue(@Value("${BACKUP_SERVICE_BUS_QUEUE}") String name) {
        if (name == null || name.isBlank() || !name.equals(name.trim())
                || ServiceBusConfig.IMAGE_PROCESSING_QUEUE.equalsIgnoreCase(name)) {
            throw new IllegalArgumentException("BACKUP_SERVICE_BUS_QUEUE must identify a separate queue");
        }
        this.name = name;
    }

    public String name() {
        return name;
    }
}
