// Grants a principal the built-in "Cosmos DB Built-in Data Contributor" data-plane role.
// Cosmos DB data-plane RBAC is separate from Azure RBAC (Microsoft.Authorization).
param accountName string
param principalId string

var dataContributorRoleId = '00000000-0000-0000-0000-000000000002'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: accountName
}

resource dataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: account
  name: guid(account.id, principalId, dataContributorRoleId)
  properties: {
    roleDefinitionId: '${account.id}/sqlRoleDefinitions/${dataContributorRoleId}'
    principalId: principalId
    scope: account.id
  }
}
