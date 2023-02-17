param timeStamp string = utcNow('yyyyMMddHHmm')
param orgPrefix string
param appPrefix string
param regionCode string
param location string = resourceGroup().location
@maxLength(16)
@description('The full prefix is the combination of the org prefix and app prefix and cannot exceed 16 characters in order to avoid deployment failures with certain PaaS resources such as storage or key vault')
param fullPrefix string = '${orgPrefix}-${appPrefix}'
param tags object = {}

var resourcePrefix = '${fullPrefix}-${regionCode}'
var workloadVnetName = '${resourcePrefix}-workload'
var tenantId = subscription().tenantId
var networkResourceGroupName = '${fullPrefix}-network'
var dnsResourceGroupName = '${fullPrefix}-dns'

//NOTE: This is set to false for ease of testing and rapid iteration on changes.  For real workloads this should be set to true
var enableSoftDeleteForKeyVault = false

/*
// TODO - Refactor to parameterize vnet name
// TODO - This is all jacked up around managed identities
module aks 'modules/aks.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-aks'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    subnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${orgPrefix}-network/providers/Microsoft.Network/virtualNetworks/${appPrefix}-vnet/subnets/aks'
  }
}
*/

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

module vmPasswordSecret 'modules/keyVaultSecrent.bicep' = {
  name: '${timeStamp}-${resourcePrefix}-kvSecret'
  params: {
    parentKeyVaultName: keyVault.outputs.name
    secretName: 'vmPassword'
    secretValue: 'TODO'
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
