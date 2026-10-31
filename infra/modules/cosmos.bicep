// Cosmos DB for NoSQL, serverless capacity, Entra ID auth only.
param name string
param location string
param tags object = {}
param databaseName string
param containerName string

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    // Keys cannot be used at all; callers need a data-plane role assignment.
    disableLocalAuth: true
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/customerId'
        ]
        kind: 'Hash'
        version: 2
      }
      // Index only the fields we filter or sort on. Cheaper writes, smaller index.
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/customerId/?'
          }
          {
            path: '/createdAt/?'
          }
          {
            path: '/status/?'
          }
        ]
        excludedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

output name string = account.name
output endpoint string = account.properties.documentEndpoint
