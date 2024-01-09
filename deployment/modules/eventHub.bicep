param eventHubNames array
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param roleAssignmentDetails array = []
param timeStamp string
param vnetName string
param zoneRedundant bool

resource eventHubNameSpace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: '${resourcePrefix}-ehns'
  location: location
  properties: {
    zoneRedundant: zoneRedundant
    // publicNetworkAccess: 'Disabled' - This won't be available until 2022-01-01-preview goes GA
  }
  sku: {
    name: 'Premium'
    capacity: 1
  }
}

resource eventHubs 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = [for eventHubName in eventHubNames: {
  name: eventHubName
  parent: eventHubNameSpace
  properties: {
    partitionCount: 20
  }
}]

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleAssignment in roleAssignmentDetails: {
  name: guid(eventHubNameSpace.id, roleAssignment.roleDefinitionId, resourceGroup().id)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionId)
    principalId: roleAssignment.principalId
  }
  scope: eventHubNameSpace
}]

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-pe-ehns'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-ehns'
    serviceResourceId: eventHubNameSpace.id
    dnsZoneName: 'privatelink.servicebus.windows.net'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'namespace'
  }
}

output hostName string = '${eventHubNameSpace.name}.servicebus.windows.net'
