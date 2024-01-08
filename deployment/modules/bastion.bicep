param prefix string
param subnetId string
param location string = resourceGroup().location

@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

resource bastionIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: '${prefix}-bastion-ip'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: { name: sku }
}

resource bastion 'Microsoft.Network/bastionHosts@2020-06-01' = {
  name: '${prefix}-bastion'
  location: location
  properties: {
    ipConfigurations: [
      { 
        name: 'bastionConf', properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: bastionIP.id
          }
        }
      }
    ]
  }
}
