@description('Location for the managed identity.')
param location string

@description('Name of the user-assigned managed identity used by the web and worker Container Apps workload.')
param identityName string

@description('Tags to apply to the resource.')
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

@description('Resource ID of the user-assigned managed identity.')
output id string = identity.id

@description('Principal (object) ID of the user-assigned managed identity, used for RBAC role assignments.')
output principalId string = identity.properties.principalId

@description('Client ID (application ID) of the user-assigned managed identity, used by Spring Cloud Azure credential configuration.')
output clientId string = identity.properties.clientId

@description('Name of the user-assigned managed identity.')
output name string = identity.name
