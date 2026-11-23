@description('Location for the Container Registry.')
param location string

@description('Name of the Azure Container Registry.')
param registryName string

@description('Principal IDs of the user-assigned managed identities (web and worker) that pull images from this registry.')
param workloadIdentityPrincipalIds array

@description('Tags to apply to the resource.')
param tags object = {}

@description('Built-in "AcrPull" role definition ID.')
var acrPullRoleDefinitionId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// One AcrPull role assignment per workload managed identity (web, worker). Each Container
// App pulls images using its own identity rather than a shared one.
resource acrPullRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in workloadIdentityPrincipalIds: {
    name: guid(registry.id, principalId, acrPullRoleDefinitionId)
    scope: registry
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleDefinitionId)
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

@description('Resource ID of the Container Registry.')
output id string = registry.id

@description('Login server (FQDN) of the Container Registry.')
output loginServer string = registry.properties.loginServer

@description('Name of the Container Registry.')
output name string = registry.name
