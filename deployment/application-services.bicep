param appPrefix string
param corePrefix string
@maxLength(16)
@description('The full prefix is the combination of the org prefix and app prefix and cannot exceed 16 characters in order to avoid deployment failures with certain PaaS resources such as storage or key vault')
param fullPrefix string = '${orgPrefix}-${appPrefix}'
param location string = resourceGroup().location
param orgPrefix string
param regionCode string
param storageSkuName string = 'Standard_LRS'
param tags object = {}
param timeStamp string = utcNow('yyyyMMddHHmm')
param zoneRedundant bool = false

var resourcePrefix = '${fullPrefix}-${regionCode}'
var workloadVnetName = '${resourcePrefix}-workload'
var tenantId = subscription().tenantId
var networkResourceGroupName = '${fullPrefix}-network'
var dnsResourceGroupName = '${fullPrefix}-dns'
var acrPullMiName = '${resourcePrefix}-mi-acrPull'
var keyVaultUserMiName = '${resourcePrefix}-mi-kvSecretsUser'

//NOTE: This is set to false for ease of testing and rapid iteration on changes.  For real workloads this should be set to true
var enableSoftDeleteForKeyVault = false

var entities = [
  'poc.customers.addresses'
]

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
  name: '${timeStamp}-kvSecret-vmPassword'
  params: {
    parentKeyVaultName: keyVault.outputs.name
    secretName: 'vmPassword'
    secretValue: 'TODO'
  }
}

module eventHub 'Modules/eventHub.bicep' = {
  name: '${timeStamp}-eventHub'
  params: {
    eventHubNames: entities
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    roleAssignmentDetails: [
      {
        roleDefinitionId: '2b629674-e913-4c01-ae53-ef4638d8f975' // Event Hubs Data Sender - https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
        principalId: ehProducerFunction.outputs.principalId
      }
      {
        roleDefinitionId: 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde' // Event Hubs Data Receiver - https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
        principalId: ehConsumerFunction.outputs.principalId
      }
    ]
    timeStamp: timeStamp
    vnetName: workloadVnetName
    zoneRedundant: zoneRedundant
  }
  dependsOn: [
    ehProducerFunction
    ehConsumerFunction
  ]
}

module serviceBus 'Modules/serviceBus.bicep' = {
  name: '${timeStamp}-serviceBus'
  params: {
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    queueNames: entities
    resourcePrefix: resourcePrefix
    roleAssignmentDetails: [
      {
        roleDefinitionId: '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39' // Service Bus Sender - https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
        principalId: ehConsumerFunction.outputs.principalId
      }
      {
        roleDefinitionId: '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0' // Service Bus Receiver - https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
        principalId: sbConsumerFunction.outputs.principalId
      }
    ]
    timeStamp: timeStamp
    vnetName: workloadVnetName
    zoneRedundant: zoneRedundant
  }
  dependsOn: [
    ehConsumerFunction
    sbConsumerFunction
  ]
}

module cosmos 'Modules/cosmos.bicep' = {
  name: '${timeStamp}-cosmos'
  params: {
    principalIdDetails: [ //These system assigned managed identities will be granted the appropriate roles on the Cosmos DB account
      {
        name: guid(ehProducerFunction.outputs.principalId)
        principalId: ehProducerFunction.outputs.principalId
      }
      {
        name: guid(sbConsumerFunction.outputs.principalId)
        principalId: sbConsumerFunction.outputs.principalId
      }
    ]
    location: location
    networkResourceGroupName: networkResourceGroupName
    dnsResourceGroupName: dnsResourceGroupName
    resourcePrefix: resourcePrefix
    timeStamp: timeStamp
    vnetName: workloadVnetName
  }
}

module ehProducerStorage 'Modules/storageAccount.bicep' = {
  name: '${timeStamp}-ehProducer-storage'
  params: {
    defaultAction: 'Allow'
    location: location
    storageAccountName: length('${format('{0}sa', replace(resourcePrefix, '-', ''))}ehproducer') > 24 ? substring('${format('{0}sa', replace(resourcePrefix, '-', ''))}ehproducer', 0, 24) : '${format('{0}sa', replace(resourcePrefix, '-', ''))}ehproducer'
    storageSkuName: storageSkuName
    targetSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/ehProducer'
  }
}

module ehProducerFunction 'Modules/functionApp.bicep' = {
  name: '${timeStamp}-ehProducer-fa'
  params: {
    acrPullMiName: acrPullMiName
    dockerImageAndTag: 'cdcehproducer:latest'
    functionAppNameSuffix: 'ehProducer'
    functionSpecificAppSettings: [
      {
        name: 'ExternalApiUri'
        value: 'http://api.contoso.com'
      }
      {
        name: 'CosmosHost'
        value: 'https://${resourcePrefix}-acdb.documents.azure.com:443'
      }
      {
        name: 'CosmosAuthToken'
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
    ]
    functionSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/ehProducer'
    keyVaultUserMiName: keyVaultUserMiName
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
    appInsights
    ehProducerStorage
  ]
}

//Hard coded private endpoint for the EH Producer FA into the Hub VNET
module privateEndpoint 'modules/privateEndpoint.bicep' = {
  name: '${timeStamp}-workload-functionApp-privateEndpoint'
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
    ehProducerFunction
  ]
}

module ehConsumerStorage 'Modules/storageAccount.bicep' = {
  name: '${timeStamp}-ehConsumer-storage'
  params: {
    defaultAction: 'Allow'
    location: location
    storageAccountName: length('${format('{0}sa', replace(resourcePrefix, '-', ''))}ehconsumer') > 24 ? substring('${format('{0}sa', replace(resourcePrefix, '-', ''))}ehconsumer', 0, 24) : '${format('{0}sa', replace(resourcePrefix, '-', ''))}ehconsumer'
    storageSkuName: storageSkuName
    targetSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/ehConsumer'
  }
}

module ehConsumerFunction 'Modules/functionApp.bicep' = {
  name: '${timeStamp}-ehConsumer-fa'
  params: {
    acrPullMiName: acrPullMiName
    dockerImageAndTag: 'cdcehconsumer:latest'
    functionAppNameSuffix: 'ehConsumer'
    functionSpecificAppSettings: [
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
    functionSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/ehConsumer'
    keyVaultUserMiName: keyVaultUserMiName
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
    appInsights
    ehConsumerStorage
  ]
}

module sbConsumerStorage 'Modules/storageAccount.bicep' = {
  name: '${timeStamp}-sbConsumer-storage'
  params: {
    defaultAction: 'Allow'
    location: location
    storageAccountName: length('${format('{0}sa', replace(resourcePrefix, '-', ''))}sbconsumer') > 24 ? substring('${format('{0}sa', replace(resourcePrefix, '-', ''))}sbconsumer', 0, 24) : '${format('{0}sa', replace(resourcePrefix, '-', ''))}sbconsumer'
    storageSkuName: storageSkuName
    targetSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/sbConsumer'
  }
}

module sbConsumerFunction 'Modules/functionApp.bicep' = {
  name: '${timeStamp}-sbConsumer-fa'
  params: {
    acrPullMiName: acrPullMiName
    dockerImageAndTag: 'cdcsbconsumer:latest'
    functionAppNameSuffix: 'sbConsumer'
    functionSpecificAppSettings: [
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
      {
        name: 'ExternalApiUri'
        value: 'http://api.contoso.com'
      }
    ]
    functionSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${networkResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${workloadVnetName}/subnets/sbConsumer'
    keyVaultUserMiName: keyVaultUserMiName
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
    appInsights
    sbConsumerStorage
  ]
}
