param enableSoftDelete bool
param keyVaultUserMiName string
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param tags object
param tenantId string = subscription().tenantId
param vnetName string


param subnetName string
param updateSecret bool = false
param secretName string = ''
@secure()
param secretValue string = ''
#disable-next-line secure-secrets-in-params   // Doesn't contain a secret
param secretsReaderObjectId string = ''
@allowed([
  'ServicePrincipal'
  'User'
])
#disable-next-line secure-secrets-in-params   // Doesn't contain a secret
param secretsReaderObjectType string = 'ServicePrincipal'

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

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
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
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
    privateEndpointName: '${keyVault.name}-vaultendpoint'
    serviceResourceId: keyVault.id
    dnsZoneName: 'privatelink.vaultcore.azure.net'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: subnetName
    groupId: 'vault'
  }
}

resource keyVaultSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (updateSecret) {
  parent: keyVault
  name: secretName
  properties: {
    value: secretValue
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(tenantId, keyVault.id, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: secretsReaderObjectId
    principalType: secretsReaderObjectType
  }
}

output keyVaultUri string = keyVault.properties.vaultUri
output name string = keyVault.name
