// learn-azure: serverless orders API
// Flex Consumption Function App + Storage queue + Cosmos DB (serverless) + App Insights.
// Every data-plane connection uses the app's managed identity. No keys or connection
// strings for Storage or Cosmos DB are created or stored.
targetScope = 'resourceGroup'

@description('Short prefix for resource names, 3-11 characters.')
@minLength(3)
@maxLength(11)
param namePrefix string

@description('Deployment environment.')
@allowed([
  'dev'
  'prod'
])
param environment string = 'dev'

@description('Azure region for every resource. Defaults to the resource group region.')
param location string = resourceGroup().location

@description('Tags applied to every resource.')
param tags object = {}

@description('Upper bound on Flex Consumption instances. Caps cost and downstream load.')
@minValue(1)
@maxValue(1000)
param maximumInstanceCount int = 100

// Deterministic per resource group, so redeploys are idempotent.
var suffix = uniqueString(resourceGroup().id)
var baseName = '${namePrefix}-${environment}'
var storageName = toLower(take('${replace(namePrefix, '-', '')}${environment}${suffix}', 24))
var deploymentContainerName = 'app-package'
var queueName = 'orders'
var cosmosDatabase = 'shop'
var cosmosContainer = 'orders'

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    name: baseName
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: storageName
    location: location
    tags: tags
    queueName: queueName
    deploymentContainerName: deploymentContainerName
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    name: '${baseName}-cosmos-${suffix}'
    location: location
    tags: tags
    databaseName: cosmosDatabase
    containerName: cosmosContainer
  }
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionapp'
  params: {
    name: '${baseName}-func-${suffix}'
    location: location
    tags: tags
    storageAccountName: storage.outputs.name
    deploymentContainerName: deploymentContainerName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    cosmosEndpoint: cosmos.outputs.endpoint
    cosmosDatabase: cosmosDatabase
    cosmosContainer: cosmosContainer
    queueName: queueName
    maximumInstanceCount: maximumInstanceCount
  }
}

// Separate module breaks the cycle: Cosmos must exist before the app (endpoint setting),
// and the app identity must exist before the Cosmos role assignment.
module cosmosAccess 'modules/cosmos-access.bicep' = {
  name: 'cosmos-access'
  params: {
    accountName: cosmos.outputs.name
    principalId: functionApp.outputs.principalId
  }
}

output functionAppName string = functionApp.outputs.name
output functionAppUrl string = 'https://${functionApp.outputs.defaultHostName}'
output storageAccountName string = storage.outputs.name
output cosmosAccountName string = cosmos.outputs.name
