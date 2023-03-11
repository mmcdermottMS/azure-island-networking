param acrPullMiName string
param dockerImageAndTag string
param functionAppNameSuffix string
param functionSpecificAppSettings array
param functionSubnetId string
param keyVaultUserMiName string
param location string
param networkResourceGroupName string
param dnsResourceGroupName string
param resourcePrefix string
param storageSkuName string
param tags object
param timeStamp string
param vnetName string
param zoneRedundant bool

var functionAppName = '${resourcePrefix}-fa-${functionAppNameSuffix}'

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${resourcePrefix}-ai'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-09-01' existing = {
  name: format('{0}cr', replace(resourcePrefix, '-', ''))
}

var storageAccountName = '${format('{0}sa', replace(resourcePrefix, '-', ''))}${toLower(functionAppNameSuffix)}'
var finalStorageAccountName = length(storageAccountName) > 24 ? substring(storageAccountName, 0, 24) : storageAccountName

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' existing = {
  name: finalStorageAccountName
}
var storageConnString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

module asp 'appServicePlan.bicep' = {
  name: '${timeStamp}-${functionAppNameSuffix}-asp'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    appNameSuffix: functionAppNameSuffix
    serverOS: 'Linux'
    zoneRedundant: zoneRedundant
    skuName: 'EP1'
    skuTier: 'ElasticPremium'
  }
}

var baseAppSettings = [
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: appInsights.properties.InstrumentationKey
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsights.properties.ConnectionString
  }
  {
    name: 'AzureWebJobsStorage'
    value: storageConnString
  }
  {
    name: 'DOCKER_REGISTRY_SERVER_URL'
    value: 'https://${containerRegistry.name}.azurecr.io'
  }
  {
    name: 'DOCKER_ENABLE_CI'
    value: 'true'
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'dotnet'
  }
  {
    name: 'SCALE_CONTROLLER_LOGGING_ENABLED'
    value: 'AppInsights:Verbose'
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: storageConnString
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: '${toLower(functionAppName)}-${substring(uniqueString(functionAppName), 0, 4)}'
  }
  {
    name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
    value: 'false'
  }
]

resource acrPullMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: acrPullMiName
}

resource keyVaultSecretsUserMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: keyVaultUserMiName
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux,container'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${acrPullMi.id}': {
      }
      '${keyVaultSecretsUserMi.id}': {
      }
    }
  }
  properties: {
    serverFarmId: asp.outputs.resourceId
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnetId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${dockerImageAndTag}'
      vnetRouteAllEnabled: true
      functionsRuntimeScaleMonitoringEnabled: true
      appSettings: concat(baseAppSettings, functionSpecificAppSettings)
    }
  }
  tags: tags
}

module privateEndpoint 'privateendpoint.bicep' = {
  name: '${timeStamp}-pe-${functionAppNameSuffix}'
  scope: resourceGroup(networkResourceGroupName)
  params: {
    location: location
    privateEndpointName: '${resourcePrefix}-pe-${functionAppNameSuffix}'
    serviceResourceId: functionApp.id
    dnsZoneName: 'privatelink.azurewebsites.net'
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    vnetName: vnetName
    subnetName: 'privateEndpoints'
    groupId: 'sites'
  }
}

// HACK: This is a total hack.  If you initially deploy a function app's storage account with a default action of
// 'Deny', the deployment of the function app (with storage configuration) will fail.  So need to do the initial 
// deployment of the storage account with networking open, then deploy the function app, then redeploy the same
// storage account with networking locked down
module networkLockedStorage 'storage.bicep' = {
  name: '${timeStamp}-${functionAppNameSuffix}-lockedStorage'
  params: {
    defaultAction: 'Deny'
    location: location
    storageAccountName: finalStorageAccountName
    storageSkuName: storageSkuName
    targetSubnetId: functionSubnetId
  }
  dependsOn: [
    functionApp
  ]
}

var roleDefinitionID = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var principalId = functionApp.identity.principalId
var roleAssignmentName= guid(functionApp.id, roleDefinitionID, resourceGroup().id)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01'= {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionID)
    principalId: principalId
  }
  scope: storageAccount
}
