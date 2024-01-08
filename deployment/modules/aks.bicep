//param acrPullMiName string
//param keyVaultUserMiName string
param fullPrefix string
param linuxAdminUsername string = 'adminUser'
param location string
param networkContributorMiName string
//param privateLinkServiceIp string
param resourcePrefix string
param subnetId string
param tags object
param keyData string


resource networkContributorMi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: networkContributorMiName
}


resource aks 'Microsoft.ContainerService/managedClusters@2023-09-01' = {
  name: '${resourcePrefix}-aks'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${networkContributorMi.id}': {
      }
    }
  }
  properties: {
    dnsPrefix: '${resourcePrefix}-aks-dns'
    agentPoolProfiles: [
      {
        name: 'agentpool1'
        count: 2
        vmSize: 'Standard_B4ms'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        vnetSubnetID: subnetId
        enableNodePublicIP: false
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
      }
    ]
    networkProfile: {
      loadBalancerSku: 'Standard'
      networkPlugin: 'azure'
      networkDataplane: 'azure'
      networkPolicy: 'azure'
    }
    nodeResourceGroup: '${fullPrefix}-workload-aks-node'
    linuxProfile: {
      adminUsername: linuxAdminUsername
      ssh: {
        publicKeys: [
          {
            keyData: keyData
          }
        ]
      }
    }
  }
  sku: {
    name: 'Basic'
    tier: 'Free'
  }
  tags: tags
}

/*
resource privateLinkService 'Microsoft.Network/privateLinkServices@2022-07-01' = {
  name: '${resourcePrefix}-pls-aks'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'aks-1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateLinkServiceIp//''
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    visibility: {
      subscriptions: [
        subscription().id
      ]
    }
    autoApproval: {
      subscriptions: [
        subscription().id
      ]
    }
  }
  tags: tags
}
*/
