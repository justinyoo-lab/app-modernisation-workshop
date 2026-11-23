targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the azd-style environment (used to derive a unique resource token). Lowercase alphanumeric and hyphens only.')
param environmentName string

@description('Primary location for all resources.')
@allowed([
  'centralus'
  'swedencentral'
  'southeastasia'
  'westus3'
  'westcentralus'
])
param location string = 'centralus'

@description('Microsoft Entra (Azure AD) principal name (e.g. UPN or group display name) of the one-time DATABASE OPERATOR allowed to connect as the PostgreSQL Entra admin and run the reviewable schema-initialization script in infra/database/init.sql. This operator is intentionally distinct from the web/worker workload managed identities created by this template and must never be used by the running application.')
param dbOperatorPrincipalName string

@description('Microsoft Entra object ID of the database operator principal above.')
param dbOperatorObjectId string

@description('Principal type of the database operator principal above.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param dbOperatorPrincipalType string = 'User'

@description('Common tags applied to all resources.')
param tags object = {
  'azd-env-name': environmentName
}

// uniqueString-based resource token, per IaC rules (resourceGroup scope variant).
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)

// Resource names follow az{resourcePrefix<=3 chars}{resourceToken} convention.
var webIdentityName = 'idw${resourceToken}'
var workerIdentityName = 'ido${resourceToken}'
var registryName = 'acr${resourceToken}'
var logAnalyticsName = 'log${resourceToken}'
var containerAppsEnvName = 'cae${resourceToken}'
var webContainerAppName = 'caw${resourceToken}'
var workerContainerAppName = 'cao${resourceToken}'
var postgresServerName = 'pg${resourceToken}'
var serviceBusNamespaceName = 'sb${resourceToken}'
// Storage account names: lowercase alphanumeric only, <= 24 chars total.
var storageAccountName = take('st${resourceToken}', 24)

var postgresDatabaseName = 'assets_manager'
var serviceBusQueueName = 'image-processing'
var blobContainerName = 'assets'

// ---------------------------------------------------------------------------
// Identity: one user-assigned managed identity per workload (web, worker), so
// each can be granted strictly least-privilege, distinct RBAC role assignments
// instead of sharing a single identity with the union of both apps' permissions.
// ---------------------------------------------------------------------------
module webIdentity 'modules/identity.bicep' = {
  name: 'webIdentity'
  params: {
    location: location
    identityName: webIdentityName
    tags: tags
  }
}

module workerIdentity 'modules/identity.bicep' = {
  name: 'workerIdentity'
  params: {
    location: location
    identityName: workerIdentityName
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Container Registry + AcrPull role assignments (ARM/control-plane role, kept
// distinct from the PostgreSQL database-level principal grants below).
// ---------------------------------------------------------------------------
module containerRegistry 'modules/containerregistry.bicep' = {
  name: 'containerRegistry'
  params: {
    location: location
    registryName: registryName
    workloadIdentityPrincipalIds: [
      webIdentity.outputs.principalId
      workerIdentity.outputs.principalId
    ]
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Log Analytics + Container Apps environment
// ---------------------------------------------------------------------------
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'logAnalytics'
  params: {
    location: location
    workspaceName: logAnalyticsName
    tags: tags
  }
}

module containerAppsEnvironment 'modules/containerappenv.bicep' = {
  name: 'containerAppsEnvironment'
  params: {
    location: location
    environmentName: containerAppsEnvName
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalytics.outputs.sharedKey
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server: Entra-only auth (no password auth at all). ARM
// roles granted on this resource (none needed beyond deployment) are entirely
// separate from the database-level grants made by the reviewable
// infra/database/init.sql script, which the operator below executes manually.
// ---------------------------------------------------------------------------
module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql'
  params: {
    location: location
    serverName: postgresServerName
    databaseName: postgresDatabaseName
    entraAdminPrincipalName: dbOperatorPrincipalName
    entraAdminObjectId: dbOperatorObjectId
    entraAdminPrincipalType: dbOperatorPrincipalType
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Service Bus namespace + queue, least-privilege Data Sender/Receiver roles.
// ---------------------------------------------------------------------------
module serviceBus 'modules/servicebus.bicep' = {
  name: 'serviceBus'
  params: {
    location: location
    namespaceName: serviceBusNamespaceName
    queueName: serviceBusQueueName
    webIdentityPrincipalId: webIdentity.outputs.principalId
    workerIdentityPrincipalId: workerIdentity.outputs.principalId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Private Blob Storage, least-privilege Storage Blob Data Contributor role
// scoped to the single container (never account- or Owner-level).
// ---------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageAccountName: storageAccountName
    containerName: blobContainerName
    webIdentityPrincipalId: webIdentity.outputs.principalId
    workerIdentityPrincipalId: workerIdentity.outputs.principalId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Shared, non-secret environment variables (names match the externalized
// placeholders already present in web/worker application.properties).
// ---------------------------------------------------------------------------
var sharedEnvironmentVariables = [
  {
    name: 'SERVICE_BUS_NAMESPACE'
    value: serviceBus.outputs.name
  }
  {
    name: 'AZURE_STORAGE_BLOB_ENDPOINT'
    value: storage.outputs.blobEndpoint
  }
  {
    name: 'AZURE_STORAGE_CONTAINER_NAME'
    value: storage.outputs.containerName
  }
  {
    name: 'POSTGRESQL_SERVER'
    value: postgresql.outputs.name
  }
  {
    name: 'POSTGRESQL_DATABASE'
    value: postgresql.outputs.databaseName
  }
]

// NOTE: POSTGRESQL_USERNAME and AZURE_MANAGED_IDENTITY_CLIENT_ID are appended per-app
// below because they differ between web and worker (each workload identity is distinct,
// and each identity's own name becomes its POSTGRESQL_USERNAME database principal, which
// infra/database/init.sql grants access to — see that file for the exact GRANT statements
// to review/run separately).

module webContainerApp 'modules/containerapp.bicep' = {
  name: 'webContainerApp'
  params: {
    location: location
    containerAppName: webContainerAppName
    environmentId: containerAppsEnvironment.outputs.id
    identityResourceId: webIdentity.outputs.id
    registryLoginServer: containerRegistry.outputs.loginServer
    enableIngress: true
    targetPort: 8080
    environmentVariables: concat(sharedEnvironmentVariables, [
      {
        name: 'AZURE_MANAGED_IDENTITY_CLIENT_ID'
        value: webIdentity.outputs.clientId
      }
      {
        name: 'POSTGRESQL_USERNAME'
        value: webIdentity.outputs.name
      }
    ])
    tags: tags
  }
}

module workerContainerApp 'modules/containerapp.bicep' = {
  name: 'workerContainerApp'
  params: {
    location: location
    containerAppName: workerContainerAppName
    environmentId: containerAppsEnvironment.outputs.id
    identityResourceId: workerIdentity.outputs.id
    registryLoginServer: containerRegistry.outputs.loginServer
    enableIngress: false
    environmentVariables: concat(sharedEnvironmentVariables, [
      {
        name: 'AZURE_MANAGED_IDENTITY_CLIENT_ID'
        value: workerIdentity.outputs.clientId
      }
      {
        name: 'POSTGRESQL_USERNAME'
        value: workerIdentity.outputs.name
      }
    ])
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs (non-secret only; no connection strings, keys, or passwords).
// ---------------------------------------------------------------------------
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output WEB_CONTAINER_APP_NAME string = webContainerApp.outputs.name
output WEB_CONTAINER_APP_FQDN string = webContainerApp.outputs.fqdn
output WORKER_CONTAINER_APP_NAME string = workerContainerApp.outputs.name
output WEB_MANAGED_IDENTITY_CLIENT_ID string = webIdentity.outputs.clientId
output WORKER_MANAGED_IDENTITY_CLIENT_ID string = workerIdentity.outputs.clientId
output WEB_MANAGED_IDENTITY_NAME string = webIdentity.outputs.name
output WORKER_MANAGED_IDENTITY_NAME string = workerIdentity.outputs.name
output POSTGRESQL_SERVER_NAME string = postgresql.outputs.name
output POSTGRESQL_SERVER_FQDN string = postgresql.outputs.fqdn
output POSTGRESQL_DATABASE_NAME string = postgresql.outputs.databaseName
output SERVICE_BUS_NAMESPACE string = serviceBus.outputs.name
output SERVICE_BUS_QUEUE_NAME string = serviceBus.outputs.queueName
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint
output AZURE_STORAGE_CONTAINER_NAME string = storage.outputs.containerName
