param location string
param orgPrefix string
param resourcePrefix string
param tenantId string
param timeStamp string
param vnetName string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${resourcePrefix}-kv'
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: tenantId
    accessPolicies: []
    enableSoftDelete: false
    enableRbacAuthorization: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-pe-kv'
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-kv'
    serviceResourceId: keyVault.id
    dnsZoneName: 'privatelink.azurewebsites.net'
    resourceGroupNameNetwork: '${orgPrefix}-network-rg'
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'vault'
  }
}