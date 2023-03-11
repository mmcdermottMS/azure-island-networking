param enableSoftDelete bool
param keyVaultUserMiName string
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param tags object
param tenantId string
param timeStamp string
param vnetName string

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  location: location
  name: keyVaultUserMiName
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  dependsOn: [ managedIdentity ]
  location: location
  name: '${resourcePrefix}-kv'
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: tenantId
    accessPolicies: []
    enableSoftDelete: enableSoftDelete
    enableRbacAuthorization: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
  tags: tags
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}', '4633458b-17de-408a-b874-0445c86b69e6', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  scope: keyVault
}

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-pe-kv'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-kv'
    serviceResourceId: keyVault.id
    dnsZoneName: 'privatelink.vaultcore.azure.net'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'vault'
  }
}

output name string = keyVault.name
