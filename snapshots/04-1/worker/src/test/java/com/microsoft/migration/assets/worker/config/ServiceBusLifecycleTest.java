package com.microsoft.migration.assets.worker.config;

import com.azure.messaging.servicebus.ServiceBusProcessorClient;
import com.azure.spring.messaging.servicebus.core.ServiceBusProcessorFactory;
import com.azure.spring.messaging.servicebus.core.listener.ServiceBusMessageListenerContainer;
import com.azure.spring.messaging.servicebus.core.properties.ServiceBusContainerProperties;
import org.junit.jupiter.api.Test;
import org.springframework.context.support.GenericApplicationContext;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ServiceBusLifecycleTest {
    @Test
    void springContextStopsTheListenerOnClose() {
        ServiceBusProcessorFactory factory = mock(ServiceBusProcessorFactory.class);
        ServiceBusProcessorClient processor = mock(ServiceBusProcessorClient.class);
        ServiceBusContainerProperties properties = new ServiceBusContainerProperties();
        properties.setEntityName(ServiceBusConfig.IMAGE_PROCESSING_QUEUE);
        when(factory.createProcessor(ServiceBusConfig.IMAGE_PROCESSING_QUEUE, properties)).thenReturn(processor);
        try (GenericApplicationContext context = new GenericApplicationContext()) {
            context.registerBean(ServiceBusMessageListenerContainer.class,
                    () -> new ServiceBusMessageListenerContainer(factory, properties));
            context.refresh();
        }
        var order = inOrder(processor);
        order.verify(processor).start();
        order.verify(processor).stop();
    }
}
