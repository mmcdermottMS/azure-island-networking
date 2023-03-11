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
var workloadResourceGroupName = '${fullPrefix}-workload'
var dnsResourceGroupName = '${fullPrefix}-dns'
var acrPullMiName = '${resourcePrefix}-mi-acrPull'
var keyVaultUserMiName = '${resourcePrefix}-mi-kvSecretsUser'
var networkContributorMiName = '${resourcePrefix}-mi-network-contributor'

//NOTE: This is set to false for ease of testing and rapid iteration on changes.  For real workloads this should be set to true
var enableSoftDeleteForKeyVault = false

module monitoring 'Modules/monitoring.bicep' = {
  name: '${timeStamp}-monitoring'
  params: {
    location: location
    resourcePrefix: resourcePrefix
  }
}

module keyVault 'Modules/keyVault.bicep' = {
  name: '${timeStamp}-kv'
  params: {
    enableSoftDelete: enableSoftDeleteForKeyVault
    keyVaultUserMiName: keyVaultUserMiName
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
  name: '${timeStamp}-kvSecret'
  params: {
    parentKeyVaultName: keyVault.outputs.name
    secretName: 'vmPassword'
    secretValue: 'TODO'
  }
}

module containerRegistry 'Modules/containerRegistry.bicep' = {
  name: '${timeStamp}-acr'
  params: {
    acrPullMiName: acrPullMiName
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    tags: tags
    timeStamp: timeStamp
    vnetName: workloadVnetName
  }
}

module springApps 'modules/springApps.bicep' = {
  name: '${timeStamp}-springApps'
  params: {
    appSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${fullPrefix}-network/providers/Microsoft.Network/virtualNetworks/${resourcePrefix}-workload/subnets/spa-apps'
    location: location
    resourpcePrefix: resourcePrefix
    serviceRuntimeSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${fullPrefix}-network/providers/Microsoft.Network/virtualNetworks/${resourcePrefix}-workload/subnets/spa-runtime'
  }
}
