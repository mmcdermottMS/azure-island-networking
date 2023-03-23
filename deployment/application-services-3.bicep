param appPrefix string
param corePrefix string
param timeStamp string = utcNow('yyyyMMddHHmm')
param orgPrefix string
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
var keyVaultUserMiName = '${resourcePrefix}-mi-kvSecretsUser'

//NOTE: This is set to false for ease of testing and rapid iteration on changes.  For real workloads this should be set to true
var enableSoftDeleteForKeyVault = false

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: '${orgPrefix}-core-${regionCode}-law'
  scope: resourceGroup('${orgPrefix}-${corePrefix}-monitoring')
}

module appInsights 'modules/appInsights.bicep' = {
  name: '${timeStamp}-ai'
  params: {
    location: location
    logAnalyticsId: logAnalytics.id
    resourcePrefix: resourcePrefix
    tags: tags
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

module networkRoleAssignment 'modules/roleAssignment.bicep' = {
  name: '${timeStamp}-network-owner-role-assignment'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    principalId: '77e44c53-4911-427e-83c2-e2a52f569dee' //ID of Azure Spring Cloud Resource Provider -- Different per tenant -- use: az ad sp show --id e8de9221-a19c-4c81-b814-fd37c6caf9d2 --query id --output tsv
    roleDefinitionId: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' //ID of Owner Role
  }
}

module springApps 'modules/springApps.bicep' = {
  name: '${timeStamp}-springApps'
  params: {
    appSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${fullPrefix}-network/providers/Microsoft.Network/virtualNetworks/${resourcePrefix}-workload/subnets/spa-apps'
    fullPrefix: fullPrefix
    location: location
    resourcePrefix: resourcePrefix
    serviceRuntimeSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${fullPrefix}-network/providers/Microsoft.Network/virtualNetworks/${resourcePrefix}-workload/subnets/spa-runtime'
  }
}
