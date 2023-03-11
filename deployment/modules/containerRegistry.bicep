param acrPullMiName string
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param tags object
param timeStamp string
param vnetName string
var acrName = format('{0}acr', replace(resourcePrefix, '-', ''))

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: acrPullMiName
  location: location
  tags: tags
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  dependsOn: [ managedIdentity ]
  location: location
  name: acrName
  sku: {
    name: 'Premium'
  }
  tags: tags
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${managedIdentity.name}', '7f951dda-4ed3-4680-a7ca-43fe172d538d', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  scope: containerRegistry
}

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-pe-acr'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-acr'
    serviceResourceId: containerRegistry.id
    dnsZoneName: 'privatelink.azurecr.io'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'registry'
  }
}
