// Flex Consumption Function App (Linux, Node.js 22) with a system-assigned identity.
param name string
param location string
param tags object = {}
param storageAccountName string
param deploymentContainerName string
param appInsightsConnectionString string
param cosmosEndpoint string
param cosmosDatabase string
param cosmosContainer string
param queueName string

@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 100

// Built-in Azure RBAC role definition ids.
var storageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributor = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${name}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true // Linux
  }
}

resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        // Identity-based host storage: the __accountName suffix tells the runtime
        // to build blob/queue/table URIs and authenticate with the managed identity.
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storage.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'COSMOS__accountEndpoint'
          value: cosmosEndpoint
        }
        {
          name: 'COSMOS_DATABASE'
          value: cosmosDatabase
        }
        {
          name: 'COSMOS_CONTAINER'
          value: cosmosContainer
        }
        {
          name: 'ORDERS_QUEUE'
          value: queueName
        }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: instanceMemoryMB
        maximumInstanceCount: maximumInstanceCount
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
}

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in [storageBlobDataOwner, storageQueueDataContributor, storageTableDataContributor]: {
    name: guid(storage.id, site.id, roleId)
    scope: storage
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
      principalId: site.identity.principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output name string = site.name
output principalId string = site.identity.principalId
output defaultHostName string = site.properties.defaultHostName
