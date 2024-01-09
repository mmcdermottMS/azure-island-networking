param appSubnetId string
param fullPrefix string
param location string
param resourcePrefix string
param serviceRuntimeSubnetId string
param tags object

resource springApps 'Microsoft.AppPlatform/Spring@2022-12-01' = {
  name: '${resourcePrefix}-spa'
  location: location
  properties: {
    networkProfile: {
      appNetworkResourceGroup: '${fullPrefix}-workload-spa-app'
      appSubnetId: appSubnetId
      serviceRuntimeNetworkResourceGroup: '${fullPrefix}-workload-spa-svc'
      serviceRuntimeSubnetId: serviceRuntimeSubnetId
      serviceCidr: '10.0.0.0/16,10.2.0.0/16,10.3.0.1/16'
      outboundType: 'userDefinedRouting'
    }
  }
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  tags: tags
}
