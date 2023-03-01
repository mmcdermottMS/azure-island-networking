param timeStamp string = utcNow('yyyyMMddHHmm')
param orgPrefix string
param appPrefix string
param regionCode string
param location string = resourceGroup().location
param storageSkuName string = 'Standard_LRS'
param tags object = {}
param zoneRedundant bool = false
@maxLength(16)
@description('The full prefix is the combination of the org prefix and app prefix and cannot exceed 16 characters in order to avoid deployment failures with certain PaaS resources such as storage or key vault')
param fullPrefix string = '${orgPrefix}-${appPrefix}'

var resourcePrefix = '${fullPrefix}-${regionCode}'
var workloadVnetName = '${resourcePrefix}-workload'
var tenantId = subscription().tenantId
var networkResourceGroupName = '${fullPrefix}-network'
var workloadResourceGroupName = '${fullPrefix}-workload'
var dnsResourceGroupName = '${fullPrefix}-dns'

//NOTE: This is set to false for ease of testing and rapid iteration on changes.  For real workloads this should be set to true
var enableSoftDeleteForKeyVault = false

var entities = [
  'poc.customers.addresses'
]

var functionApps = [
  {
    functionAppNameSuffix: 'ehConsumer'
    dockerImageAndTag: 'cdcehconsumer:latest'
    appSettings: [
      {
        name: 'ExternalApiUri'
        value: 'http://api.contoso.com'
      }
      {
        name: 'EhNameSpace__fullyQualifiedNamespace'
        value: '${resourcePrefix}-ehns.servicebus.windows.net'
      }
      {
        name: 'EhName'
        value: entities[0]
      }
      {
        name: 'ServiceBusHostName'
        value: '${resourcePrefix}-sbns.servicebus.windows.net'
      }
      {
        name: 'QueueName'
        value: entities[0]
      }
    ]
  }
  {
    functionAppNameSuffix: 'sbConsumer'
    dockerImageAndTag: 'cdcsbconsumer:latest'
    appSettings: [
      {
        name: 'ExternalApiUri'
        value: 'http://api.contoso.com'
      }
      {
        name: 'CosmosHost'
        value: 'https://${resourcePrefix}-acdb.documents.azure.com:443'
      }
      {
        name: 'ServiceBusConnection__fullyQualifiedNamespace'
        value: '${resourcePrefix}-sbns.servicebus.windows.net'
      }
      {
        name: 'QueueName'
        value: entities[0]
      }
    ]
  }
  {
    functionAppNameSuffix: 'ehProducer'
    dockerImageAndTag: 'cdcehproducer:latest'
    appSettings: [
      {
        name: 'CosmosHost'
        value: 'https://${resourcePrefix}-acdb.documents.azure.com:443'
      }
      {
        name: 'CosmosAuthToken' //TODO: Wire this to KV
        value: ''
      }
      {
        name: 'CosmosInitialAutoscaleThroughput'
        value: '20000'
      }
      {
        name: 'EhNameSpace'
        value: '${resourcePrefix}-ehns.servicebus.windows.net'
      }
      {
        name: 'EhName'
        value: entities[0]
      }
      {
        name: 'ExternalApiUri'
        value: 'http://api.contoso.com'
      }
    ]
  }
]






var managedIdentityName = '${resourcePrefix}-mi-network-contributor'

module networkContributorMi 'modules/managedIdentity.bicep' = {
  name: '${timeStamp}-mi-network-contributor'
  scope: resourceGroup(workloadResourceGroupName)
  params: {
    location: location
    name: managedIdentityName
    tags: tags
  }
}

module networkRoleAssignment 'modules/roleAssignment.bicep' = {
  name: '${timeStamp}-network-contributor-role-assignment'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    principalId: networkContributorMi.outputs.principalId
  }
}

module aks 'modules/aks.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-aks'
  params: {
    location: location
    managedIdentityName: managedIdentityName
    resourcePrefix: resourcePrefix
    subnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${fullPrefix}-network/providers/Microsoft.Network/virtualNetworks/${resourcePrefix}-workload/subnets/aks'
  }
  dependsOn: [
    networkContributorMi
    networkRoleAssignment
  ]
}














/*
module monitoring 'Modules/monitoring.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-monitoring'
  params: {
    location: location
    resourcePrefix: resourcePrefix
  }
}

module keyVault 'Modules/keyVault.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-kv'
  params: {
    enableSoftDelete: enableSoftDeleteForKeyVault
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    tags: tags
    tenantId: tenantId
    timeStamp: timeStamp
    vnetName: workloadVnetName
  }
}

module vmPasswordSecret 'modules/keyVaultSecrent.bicep'  = {
  name: '${timeStamp}-${resourcePrefix}-kvSecret'
  params: {
    parentKeyVaultName: keyVault.outputs.name
    secretName: 'vmPassword'
    secretValue: 'TODO'
  }
}

module eventHub 'Modules/eventHub.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-eventHub'
  params: {
    eventHubNames: entities
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    timeStamp: timeStamp
    vnetName: workloadVnetName
    zoneRedundant: zoneRedundant
  }
}

module serviceBus 'Modules/serviceBus.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-serviceBus'
  params: {
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    queueNames: entities
    resourcePrefix: resourcePrefix
    timeStamp: timeStamp
    vnetName: workloadVnetName
    zoneRedundant: zoneRedundant
  }
}

module containerRegistry 'Modules/containerRegistry.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-acr'
  params: {
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    timeStamp: timeStamp
    vnetName: workloadVnetName
  }
}

module cosmos 'Modules/cosmos.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-cosmos'
  params: {
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    timeStamp: timeStamp
    vnetName: workloadVnetName
  }
}

var functionAppsCount = length(functionApps)
module storage 'Modules/storage.bicep' = [for i in range(0, functionAppsCount): {
  name: '${timeStamp}-${resourcePrefix}-${functionApps[i].functionAppNameSuffix}-storage'
  params: {
    defaultAction: 'Allow'
    location: location
    storageAccountName: length('${format('{0}sa', replace(resourcePrefix, '-', ''))}${toLower(functionApps[i].functionAppNameSuffix)}') > 24 ? substring('${format('{0}sa', replace(resourcePrefix, '-', ''))}${toLower(functionApps[i].functionAppNameSuffix)}', 0, 24) : '${format('{0}sa', replace(resourcePrefix, '-', ''))}${toLower(functionApps[i].functionAppNameSuffix)}'
    storageSkuName: storageSkuName
    targetSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/${functionApps[i].functionAppNameSuffix}'
  }
}]

module functions 'Modules/functionapp.bicep' = [for i in range(0, functionAppsCount): {
  name: '${timeStamp}-${resourcePrefix}-${functionApps[i].functionAppNameSuffix}'
  params: {
    dockerImageAndTag: functionApps[i].dockerImageAndTag
    functionAppNameSuffix: functionApps[i].functionAppNameSuffix
    functionSpecificAppSettings: functionApps[i].appSettings
    functionSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/${functionApps[i].functionAppNameSuffix}'
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    storageSkuName: storageSkuName
    tags: tags
    timeStamp: timeStamp
    vnetName: workloadVnetName
    zoneRedundant: zoneRedundant    
  }
  dependsOn: [
    monitoring
    storage
  ]
}]

//Hard coded private endpoint for the EH Producer FA into the Hub VNET
module privateEndpoint 'modules/privateendpoint.bicep' = {
  name: 'workload-functionApp-privateEndpoint'
  scope: resourceGroup('${orgPrefix}-core-network')
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-ehProducer'
    serviceResourceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${orgPrefix}-${appPrefix}-workload/providers/Microsoft.Web/sites/${resourcePrefix}-fa-ehProducer'
    dnsZoneName: 'privatelink.azurewebsites.net'
    networkResourceGroupName: '${orgPrefix}-core-network'
    dnsResourceGroupName: '${orgPrefix}-core-dns'
    vnetName: '${orgPrefix}-core-${regionCode}-hub'
    subnetName: 'services'
    groupId: 'sites'
  }
  dependsOn: [
    functions
  ]
}

*/
