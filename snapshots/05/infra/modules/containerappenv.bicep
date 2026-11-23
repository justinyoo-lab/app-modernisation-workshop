@description('Location for the Container Apps environment.')
param location string

@description('Name of the Container Apps (managed) environment.')
param environmentName string

@description('Customer ID of the Log Analytics workspace to attach for environment-level logging.')
param logAnalyticsCustomerId string

@secure()
@description('Primary shared key of the Log Analytics workspace to attach for environment-level logging.')
param logAnalyticsSharedKey string

@description('Tags to apply to the resource.')
param tags object = {}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

@description('Resource ID of the Container Apps environment.')
output id string = containerAppsEnvironment.id

@description('Name of the Container Apps environment.')
output name string = containerAppsEnvironment.name

@description('Default domain of the Container Apps environment.')
output defaultDomain string = containerAppsEnvironment.properties.defaultDomain
