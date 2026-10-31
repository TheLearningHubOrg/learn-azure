// Storage account for the Functions host, the orders queue and the deployment package.
// Shared key access is disabled: everything authenticates with Entra ID.
@minLength(3)
@maxLength(24)
param name string
param location string
param tags object = {}
param queueName string
param deploymentContainerName string

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource ordersQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: queueName
}

// The Functions runtime moves a message here after maxDequeueCount failed attempts.
resource poisonQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: '${queueName}-poison'
}

output name string = account.name
output id string = account.id
output blobEndpoint string = account.properties.primaryEndpoints.blob
