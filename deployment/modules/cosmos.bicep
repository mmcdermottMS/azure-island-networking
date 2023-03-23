param allowedPrincipalIds array = []
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param timeStamp string
param vnetName string

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: '${resourcePrefix}-acdb'
  location: location
  properties: {
    locations: [
      {
        locationName: location
      }
    ]
    databaseAccountOfferType: 'Standard'
    networkAclBypass: 'AzureServices'
    publicNetworkAccess: 'Disabled'
  }
}

resource cosmosCustomRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2022-11-15' = {
  parent: cosmos
  name: 'cosmosdb-sql-role-definition'
  properties: {
    roleName: 'cosmosdb-sql-role-definition'
    type: 'CustomRole'
    assignableScopes: [
      cosmos.id
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
        ]
      }
    ]
  }
}

resource accountName_readWriteRoleAssignmentId 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-11-15' = [for principalId in allowedPrincipalIds: {
  parent: cosmos
  name: 'custom-role-assignment-${substring(uniqueString(principalId), 0, 8)})'
  properties: {
    roleDefinitionId: cosmosCustomRole.id
    principalId: principalId
    scope: cosmos.id
  }
}]

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-pe-cosmos'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-cosmos'
    serviceResourceId: cosmos.id
    dnsZoneName: 'privatelink.documents.azure.com'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'Sql'
  }
}

output id string = cosmos.id
