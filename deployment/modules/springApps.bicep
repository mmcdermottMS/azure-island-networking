param appSubnetId string
param location string
param resourpcePrefix string
param serviceRuntimeSubnetId string

resource springApps 'Microsoft.AppPlatform/Spring@2022-12-01' = {
  name: '${resourpcePrefix}-spa'
  location: location
  properties: {
    networkProfile: {
      appSubnetId: appSubnetId
      serviceRuntimeSubnetId: serviceRuntimeSubnetId
    }
  }
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
}
