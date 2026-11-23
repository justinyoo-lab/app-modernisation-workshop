@description('Location for the Service Bus namespace.')
param location string

@description('Name of the Service Bus namespace.')
param namespaceName string

@description('Name of the image-processing queue.')
param queueName string = 'image-processing'

@description('Principal ID of the web workload managed identity (message producer).')
param webIdentityPrincipalId string

@description('Principal ID of the worker workload managed identity (message consumer).')
param workerIdentityPrincipalId string

@description('Tags to apply to the resource.')
param tags object = {}

@description('Built-in "Azure Service Bus Data Sender" role definition ID.')
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'

@description('Built-in "Azure Service Bus Data Receiver" role definition ID.')
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    // Shared Access Key policies are not disabled at the namespace level (that setting
    // only blocks SAS *connection strings*; it is still good hygiene), but the application
    // never uses a connection string: it authenticates exclusively over AMQP 1.0/TLS via
    // Azure Managed Identity (see least-privilege role assignments below).
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    enablePartitioning: false
  }
}

// Least-privilege: web only sends (produces) thumbnail-processing requests.
resource webSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, webIdentityPrincipalId, serviceBusDataSenderRoleId)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: webIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// web also runs a backup consumer (BackupMessageProcessor), so it additionally needs
// receive access; still scoped only to this single queue, never namespace-wide management.
resource webReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, webIdentityPrincipalId, serviceBusDataReceiverRoleId)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: webIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Least-privilege: worker only receives (consumes) thumbnail-processing requests.
resource workerReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(queue.id, workerIdentityPrincipalId, serviceBusDataReceiverRoleId)
  scope: queue
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: workerIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('Resource ID of the Service Bus namespace.')
output id string = serviceBusNamespace.id

@description('Name of the Service Bus namespace; maps to the SERVICE_BUS_NAMESPACE application setting (Spring Cloud Azure resolves the FQDN itself).')
output name string = serviceBusNamespace.name

@description('Fully qualified namespace host name.')
output fqdn string = '${serviceBusNamespace.name}.servicebus.windows.net'

@description('Name of the image-processing queue.')
output queueName string = queue.name
