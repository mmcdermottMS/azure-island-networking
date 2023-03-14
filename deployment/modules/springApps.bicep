param appSubnetId string
param location string
param resourcePrefix string
param serviceRuntimeSubnetId string

resource springApps 'Microsoft.AppPlatform/Spring@2022-12-01' = {
  name: '${resourcePrefix}-spa'
  location: location
  properties: {
    networkProfile: {
      appNetworkResourceGroup: '${resourcePrefix}-workload-spa-app'
      appSubnetId: appSubnetId
      serviceRuntimeNetworkResourceGroup: '${resourcePrefix}-workload-spa-svc'
      serviceRuntimeSubnetId: serviceRuntimeSubnetId
      outboundType: 'userDefinedRouting'
    }
  }
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
}
