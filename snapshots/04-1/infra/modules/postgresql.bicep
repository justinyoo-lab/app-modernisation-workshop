@description('Location for the PostgreSQL Flexible Server.')
param location string

@description('Name of the PostgreSQL Flexible Server.')
param serverName string

@description('Name of the application database to create (schema is NOT initialized here; see infra/database/init.sql).')
param databaseName string = 'assets_manager'

@description('PostgreSQL major version.')
param postgresVersion string = '17'

@description('Compute SKU name for the Flexible Server.')
param skuName string = 'Standard_B1ms'

@description('Compute tier for the Flexible Server.')
param skuTier string = 'Burstable'

@description('Storage size (GiB) for the Flexible Server.')
param storageSizeGB int = 32

@description('Microsoft Entra (Azure AD) principal name of the one-time *operator* account/group permitted to run schema initialization and grant scripts. This is distinct from the workload managed identity and MUST NOT be used by the running application.')
param entraAdminPrincipalName string

@description('Microsoft Entra object ID of the operator principal above.')
param entraAdminObjectId string

@description('Principal type of the operator principal above.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param entraAdminPrincipalType string = 'User'

@description('Tags to apply to the resource.')
param tags object = {}

// Microsoft Entra-only authentication: no PostgreSQL password/admin login is created.
// The server itself grants no application-level database privileges; those are granted
// separately, out-of-band, by the reviewable infra/database/init.sql procedure executed
// by the operator principal configured above (never by this Bicep template and never by
// the workload's own managed identity).
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    storage: {
      storageSizeGB: storageSizeGB
    }
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

// Microsoft Entra administrator for the server (control-plane/ARM-adjacent operator role,
// used only to run the reviewable DB initialization script; distinct from any database-level
// principal grants made inside that script, and distinct from the workload managed identity).
resource entraAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: postgresServer
  name: entraAdminObjectId
  properties: {
    principalName: entraAdminPrincipalName
    principalType: entraAdminPrincipalType
    tenantId: subscription().tenantId
  }
}

// Allow access from Azure services (Container Apps egress uses dynamic outbound IPs).
// TLS (sslmode=require) is enforced independently by the application's JDBC URL and by
// the server default; this firewall rule only controls network reachability, not transport
// security.
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgresServer
  name: 'AllowAllAzureServicesAndResourcesWithinAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
  dependsOn: [
    entraAdmin
  ]
}

@description('Resource ID of the PostgreSQL Flexible Server.')
output id string = postgresServer.id

@description('Name of the PostgreSQL Flexible Server (without the .postgres.database.azure.com suffix); maps to the POSTGRESQL_SERVER application setting.')
output name string = postgresServer.name

@description('Fully qualified domain name of the PostgreSQL Flexible Server.')
output fqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('Name of the application database; maps to the POSTGRESQL_DATABASE application setting.')
output databaseName string = database.name
