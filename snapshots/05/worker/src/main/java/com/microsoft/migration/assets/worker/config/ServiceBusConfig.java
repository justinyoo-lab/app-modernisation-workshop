package com.microsoft.migration.assets.worker.config;

import com.azure.spring.messaging.ConsumerIdentifier;
import com.azure.spring.messaging.PropertiesSupplier;
import com.azure.spring.messaging.servicebus.core.properties.ProcessorProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class ServiceBusConfig {
    public static final String IMAGE_PROCESSING_QUEUE = "image-processing";

    /**
     * Mirrors the original RabbitMQ listener container's {@code AcknowledgeMode.MANUAL}: the
     * application explicitly completes/abandons/dead-letters each message instead of relying on
     * Service Bus auto-complete.
     * <p>
     * The {@code image-processing} queue itself (including its max-delivery-count /
     * dead-letter behavior) is provisioned out-of-band by infrastructure. This application is
     * intentionally not given a {@code ServiceBusAdministrationClient} bean: the managed identity
     * backing it is only granted least-privilege Service Bus "Data Receiver" role assignment, not
     * the management ("Owner") permissions that queue creation would require.
     */
    @Bean
    public PropertiesSupplier<ConsumerIdentifier, ProcessorProperties> processorPropertiesSupplier() {
        return key -> {
            ProcessorProperties processorProperties = new ProcessorProperties();
            processorProperties.setAutoComplete(false);
            return processorProperties;
        };
    }
}
