@description('Location for the Log Analytics workspace.')
param location string

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Tags to apply to the resource.')
param tags object = {}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

@description('Resource ID of the Log Analytics workspace.')
output id string = logAnalytics.id

@description('Customer ID (workspace ID) of the Log Analytics workspace.')
output customerId string = logAnalytics.properties.customerId

@description('Name of the Log Analytics workspace.')
output name string = logAnalytics.name

@secure()
@description('Primary shared key of the Log Analytics workspace, used only to wire the Container Apps environment logAnalyticsConfiguration.')
output sharedKey string = logAnalytics.listKeys().primarySharedKey
