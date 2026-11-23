@description('Location for the Storage Account.')
param location string

@description('Name of the Storage Account (lowercase alphanumeric, <= 24 characters).')
param storageAccountName string

@description('Name of the private blob container used for asset/thumbnail storage.')
param containerName string = 'assets'

@description('Principal ID of the web workload managed identity (read/write object storage path).')
param webIdentityPrincipalId string

@description('Principal ID of the worker workload managed identity (read/write thumbnail processing).')
param workerIdentityPrincipalId string

@description('Tags to apply to the resource.')
param tags object = {}

@description('Built-in "Storage Blob Data Contributor" role definition ID.')
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    // Passwordless-only: account key / connection-string authentication is disabled.
    allowSharedKeyAccess: false
    // No public/anonymous blob access at the account level; the container is also
    // created without a PublicAccessType, so it is private by default.
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Least-privilege: scoped to the single container, not the whole storage account, for
// both the web (upload/get/delete/list) and worker (download original / upload thumbnail)
// workload identities.
resource webBlobContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, webIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: webIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerBlobContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, workerIdentityPrincipalId, storageBlobDataContributorRoleId)
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: workerIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('Resource ID of the Storage Account.')
output id string = storageAccount.id

@description('Name of the Storage Account.')
output name string = storageAccount.name

@description('Primary Blob service endpoint; maps to the AZURE_STORAGE_BLOB_ENDPOINT application setting.')
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Name of the private blob container; maps to the AZURE_STORAGE_CONTAINER_NAME application setting.')
output containerName string = container.name
