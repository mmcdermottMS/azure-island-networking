param timeStamp string = utcNow('yyyyMMddHHmm')
param appPrefix string
param regionCode string
param location string = resourceGroup().location
param zoneRedundant bool = false

var resourcePrefix = '${appPrefix}-${regionCode}'


var functionApps = [
  {
    functionAppNameSuffix: 'ehConsumer'
    storageAccountNameSuffix: 'ehconsumer'
    dockerImageAndTag: 'cdcehconsumer:latest'
  }
  {
    functionAppNameSuffix: 'sbConsumer'
    storageAccountNameSuffix: 'sbconsumer'
    dockerImageAndTag: 'cdcsbconsumer:latest'
  }
  {
    functionAppNameSuffix: 'ehProducer'
    storageAccountNameSuffix: 'ehproducer'
    dockerImageAndTag: 'cdcehproducer:latest'
  }
]

var webApps = [
  {
    appServiceNameSuffix: 'weather'
    dockerImageAndTag: 'cdcgenericmicroserviceapi:latest'
  }
]

var entities = [
  'poc.customers.addresses'
]

// TODO - Refactor to parameterize vnet name
// TODO - This is all jacked up around managed identities
/*
var aksSubnetId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${appPrefix}-network-rg/providers/Microsoft.Network/virtualNetworks/${appPrefix}-workload-a/subnets/aks'
module aks 'modules/aks.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-aks'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    subnetId: aksSubnetId
  }
}
*/

var tenantId = subscription().tenantId
module keyVault 'Modules/keyVault.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-kv'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tenantId: tenantId
  }
}

/*
module monitoring 'Modules/monitoring.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-monitoring'
  params: {
    location: location
    resourcePrefix: resourcePrefix
  }
}

module containerRegistry 'Modules/containerRegistry.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-acr'
  params: {
    location: location
    resourcePrefix: resourcePrefix
  }
}

module eventHub 'Modules/eventHub.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-eventHub'
  params: {
    eventHubNames: entities
    location: location 
    resourcePrefix: resourcePrefix
    zoneRedundant: zoneRedundant
  }
}

module serviceBus 'Modules/serviceBus.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-serviceBus'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    zoneRedundant: zoneRedundant
    queueNames: entities
  }
}

module cosmos 'Modules/cosmos.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-cosmos'
  params: {
    location: location
    resourcePrefix: resourcePrefix
  }
}

var functionAppsCount = length(functionApps)
module functions 'Modules/functions.bicep' = [for i in range(0, functionAppsCount): {
  name: '${timeStamp}-${resourcePrefix}-${functionApps[i].functionAppNameSuffix}'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    storageSkuName: 'LRS'
    storageAccountNameSuffix: functionApps[i].storageAccountNameSuffix
    functionAppNameSuffix: functionApps[i].functionAppNameSuffix
    timeStamp: timeStamp
    zoneRedundant: zoneRedundant
    functionSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${appPrefix}-network-rg/providers/Microsoft.Network/virtualNetworks/${appPrefix}-workload-a/subnets/aks'
    dockerImageAndTag: functionApps[i].dockerImageAndTag
  }
  dependsOn: [
    monitoring
  ]
}]
*/
