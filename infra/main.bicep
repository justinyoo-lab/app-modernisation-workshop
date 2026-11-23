targetScope = 'subscription'

@minLength(1)
@maxLength(32)
param environmentName string

param location string

@secure()
@minLength(12)
@maxLength(123)
@description('Local administrator password for appmoduser. Include at least three of uppercase letters, lowercase letters, digits and special characters.')
param adminPassword string

@allowed([
  true
])
@description('Set to true only after confirming that you are eligible to run Windows 11 client licenses on Azure.')
param confirmWindowsClientLicense bool

@allowed([
  'Standard_D4s_v5'
  'Standard_D8s_v5'
  'Standard_D8ds_v5'
  'Standard_D16s_v5'
])
param vmSize string = 'Standard_D8s_v5'

@minValue(256)
@maxValue(1024)
param osDiskSizeGB int = 256

param autoShutdownEnabled bool = true

@minLength(4)
@maxLength(4)
@description('Daily auto-shutdown (deallocation) time in Korea Standard Time, in 24-hour HHmm format.')
param autoShutdownTime string = '2000'

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  workload: 'windows-app-modernization'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module workstation 'modules/workstation.bicep' = {
  name: 'workstation'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    adminPassword: adminPassword
    confirmWindowsClientLicense: confirmWindowsClientLicense
    vmSize: vmSize
    osDiskSizeGB: osDiskSizeGB
    autoShutdownEnabled: autoShutdownEnabled
    autoShutdownTime: autoShutdownTime
  }
}

module userScripts 'modules/user-scripts.bicep' = {
  name: 'user-scripts'
  scope: rg
  params: {
    location: location
    vmName: workstation.outputs.vmName
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_VM_NAME string = workstation.outputs.vmName
output AZURE_VM_ID string = workstation.outputs.vmId
output AZURE_VM_ADMIN_USERNAME string = 'appmoduser'
output AZURE_BASTION_NAME string = workstation.outputs.bastionName
output AZURE_SCRIPT_DELIVERY string = userScripts.outputs.runCommandName
