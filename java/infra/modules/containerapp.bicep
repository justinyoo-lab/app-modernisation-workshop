@description('Location for the Container App.')
param location string

@description('Name of the Container App.')
param containerAppName string

@description('Resource ID of the Container Apps (managed) environment.')
param environmentId string

@description('Resource ID of the user-assigned managed identity used by this Container App (image pull + Azure service auth).')
param identityResourceId string

@description('Login server (FQDN) of the Azure Container Registry used to pull images.')
param registryLoginServer string

@description('Whether to expose external (internet-facing) HTTP ingress. The web app needs this; the worker (background queue consumer) does not.')
param enableIngress bool = false

@description('Target port for ingress, used only when enableIngress is true.')
param targetPort int = 8080

@description('Non-secret environment variables for the application container.')
param environmentVariables array = []

@description('Tags to apply to the resource.')
param tags object = {}

// MANDATORY per container-app IaC rules: start from the base hello-world image. The real
// web/worker application image is published separately (out of scope for this
// infrastructure-only task) and swapped in post-build via `az containerapp update --image`.
var placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: registryLoginServer
          identity: identityResourceId
        }
      ]
      ingress: enableIngress ? {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
        }
      } : null
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: placeholderImage
          env: environmentVariables
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

@description('Resource ID of the Container App.')
output id string = containerApp.id

@description('Name of the Container App.')
output name string = containerApp.name

@description('Fully qualified domain name of the Container App ingress (empty when ingress is disabled).')
output fqdn string = enableIngress ? containerApp.properties.configuration.ingress.fqdn : ''
