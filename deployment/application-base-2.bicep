targetScope = 'subscription'

@allowed([
  'eastus'
  'eastus2'
  'northcentralus'
  'centralus'
  'westus'
  'westus2'
  'westus3'
])
param region string
param orgPrefix string
param appPrefix string
param corePrefix string
param regionCode string
param timeStamp string = utcNow('yyyyMMddHHmm')
param tags object = { }
param vmAdminUserName string = 'vmadmin'
@secure()
param vmAdminPwd string
param vmSubnetName string = 'util'
@maxLength(16)
@description('The full prefix is the combination of the org prefix and app prefix and cannot exceed 16 characters in order to avoid deployment failures with certain PaaS resources such as storage or key vault')
param fullPrefix string = '${orgPrefix}-${appPrefix}'

var resourcePrefix = '${orgPrefix}-${appPrefix}-${regionCode}'
var coreNetworkRgName = '${orgPrefix}-${corePrefix}-network'
var coreDnsRgName = '${orgPrefix}-${corePrefix}-dns'

resource coreNetworkRg 'Microsoft.Resources/resourceGroups@2020-06-01' existing = {
  name: coreNetworkRgName
}

resource coreDnsRg 'Microsoft.Resources/resourceGroups@2020-06-01' existing = {
  name: coreDnsRgName
}

resource workloadNetworkRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${fullPrefix}-network'
  location: region
  tags: tags
}

resource workloadDnsRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${fullPrefix}-dns'
  location: region
  tags: tags
}

resource workloadRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${fullPrefix}-workload'
  location: region
  tags: tags
}

resource utilRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${fullPrefix}-util'
  location: region
}

resource bridgeVnet 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  name: '${orgPrefix}-${corePrefix}-${regionCode}-bridge01'
  scope: resourceGroup(coreNetworkRgName)
}

resource bridgeAzFw 'Microsoft.Network/azureFirewalls@2022-05-01' existing = {
  name: '${orgPrefix}-${corePrefix}-${regionCode}-bridge01-azfw'
  scope: resourceGroup(coreNetworkRgName)
}

param islandVnetAddressSpace string = '192.168.128.0/18'
param aksSubnetAddressPrefix string = '192.168.128.0/22'          // 1019 addresses - 192.168.0.0 - 192.168.4.0
param utilSubnetAddressPrefix string = '192.168.132.0/22'         // 1019 addresses - 192.168.4.0 - 192.168.8.0
param privateEndpointAddressPrefix string = '192.168.136.0/24'    // 251  addresses - 192.168.8.0 - 192.168.9.0

module vnet 'modules/vnet.bicep' = {
  name: '${timeStamp}-vnet'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    vnetName: '${resourcePrefix}-workload'
    location: region
    addressSpaces: [
      islandVnetAddressSpace
    ]
    subnets: [
      {
        name: 'aks'
        properties: {
          addressPrefix: aksSubnetAddressPrefix
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: aksIntegrationNsg.outputs.id
          }
        }
      }
      {
        name: 'util'
        properties: {
          addressPrefix: utilSubnetAddressPrefix
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: utilNsg.outputs.id
          }
        }
      }
      {
        name: 'privateEndpoints'
        properties: {
          addressPrefix: privateEndpointAddressPrefix
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: privateEndpointsNsg.outputs.id
          }
        }
      }
    ]
  }
}

//TODO: This route table isn't quite right, but allows for communcation to app insights.  Using for now until we figure out how to route AI
// traffic correctly through the firewall
module route 'modules/udr.bicep' = {
  name: '${timeStamp}-udr'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    name: '${resourcePrefix}-udr'
    location: region
    routes: [
      {
        name: '${resourcePrefix}-egress'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
      {
        name: '${resourcePrefix}-hub'
        properties: {
          addressPrefix: '192.168.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: bridgeAzFw.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
      {
        name: '${resourcePrefix}-island'
        properties: {
          addressPrefix: '10.0.0.0/8'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: bridgeAzFw.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// NSG for AKS subnet
module aksIntegrationNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-nsg-aks'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    name: '${resourcePrefix}-workload-nsg-aks'
    location: region
    securityRules: [
      {
        name: 'AllowAnyHTTPInbound'
        properties: {
          priority: 100
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

param bridgeBastionSubnetAddressSpace string = '10.10.16.128/25' // 123 addresses - 10.10.16.128 - 10.10.0.255
param hubVnetAddressSpace string = '10.10.0.0/20'
param spokeVnetAddressSpace string = '10.10.32.0/20'

// NSG for Util subnet
module utilNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-nsg-util'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    name: '${resourcePrefix}-workload-nsg-util'
    location: region
    securityRules: [
      {
        name: 'allow-bastion'
        properties: {
          priority: 100
          direction: 'Inbound'
          protocol: '*'
          access: 'Allow'
          sourceAddressPrefix: bridgeBastionSubnetAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'allow-dns'
        properties: {
          priority: 110
          direction: 'Inbound'
          protocol: '*'
          access: 'Allow'
          sourceAddressPrefixes: [
            hubVnetAddressSpace
            spokeVnetAddressSpace
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '53'
          ]
        }
      }
    ]
  }
}

// NSG for Private Endpoints subnet
module privateEndpointsNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-nsg-pe'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    name: '${resourcePrefix}-workload-nsg-pe'
    location: region
    securityRules: [
      {
        name: 'deny-inbound-default'
        properties: {
          priority: 120
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

module vnetPeerIslandToBridge 'modules/peering.bicep' = {
  name: '${timeStamp}-islandToBridgePeering'
  scope: resourceGroup(workloadNetworkRg.name)
  params: {
    localVnetName: vnet.outputs.name
    remoteVnetName: bridgeVnet.name
    remoteVnetId: bridgeVnet.id
  }
}

module vnetPeerBridgeToIsland 'modules/peering.bicep' = {
  name: '${timeStamp}-bridgeToIslandPeering'
  scope: resourceGroup(coreNetworkRg.name)
  params: {
    localVnetName: bridgeVnet.name
    remoteVnetName: vnet.outputs.name
    remoteVnetId: vnet.outputs.id
  }
}

// Link to VNET to the Private DNS resolver
module resolverLink 'modules/dnsResolverLink.bicep' = {
  name: '${timeStamp}-dnsResolverLink'
  scope: resourceGroup(coreDnsRg.name)
  params: {
    forwardingRulesetName: 'dns-forward-ruleset-contoso'
    linkName: '${vnet.outputs.name}-link'
    vnetId: vnet.outputs.id
  }
}

// utility server for traffic testing
module utilServer 'modules/virtualMachine.bicep' = {
  name: '${timeStamp}-vm'
  scope: resourceGroup(utilRg.name)
  params: {
    adminUserName: vmAdminUserName
    adminPassword: vmAdminPwd
    networkResourceGroupName: workloadNetworkRg.name
    location: region
    vnetName: vnet.outputs.name
    subnetName: vmSubnetName
    os: 'linux'
    vmName: '${resourcePrefix}-util01'
    vmSize: 'Standard_B2ms'
  }
}

// Private DNS zone for other Azure services
module privateZoneWebsites 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-azurewebsites'
  scope: resourceGroup(workloadDnsRg.name)
  params: {
    zoneName: 'privatelink.azurewebsites.net'
  }
}

module vnetAzureWebsitesZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-azurewebsites'
  scope: resourceGroup(workloadDnsRg.name)
  dependsOn: [
    privateZoneWebsites
  ]
  params: {
    vnetName: vnet.outputs.name
    vnetId: vnet.outputs.id
    zoneName: 'privatelink.azurewebsites.net'
    autoRegistration: false
  }
}

// Private DNS zone for Azure Container Registry
module privateZoneAcr 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-acr'
  scope: resourceGroup(workloadDnsRg.name)
  params: {
    zoneName: 'privatelink.azurecr.io'
  }
}

module vnetAcrZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-acr'
  scope: resourceGroup(workloadDnsRg.name)
  dependsOn: [
    privateZoneAcr
  ]
  params: {
    vnetName: vnet.outputs.name
    vnetId: vnet.outputs.id
    zoneName: 'privatelink.azurecr.io'
    autoRegistration: false
  }
}

// Private DNS zone for Key Vault
module privateZoneKeyVault 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-keyvault'
  scope: resourceGroup(workloadDnsRg.name)
  params: {
    zoneName: 'privatelink.vaultcore.azure.net'
  }
}

module vnetKeyVaultZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-keyvault'
  scope: resourceGroup(workloadDnsRg.name)
  dependsOn: [
    privateZoneKeyVault
  ]
  params: {
    vnetName: vnet.outputs.name
    vnetId: vnet.outputs.id
    zoneName: 'privatelink.vaultcore.azure.net'
    autoRegistration: false
  }
}

// Private DNS zone for Cosmos DB
module privateZoneCosmos 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-acdb'
  scope: resourceGroup(workloadDnsRg.name)
  params: {
    zoneName: 'privatelink.documents.azure.com'
  }
}

module vnetCosmostZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-acdb'
  scope: resourceGroup(workloadDnsRg.name)
  dependsOn: [
    privateZoneCosmos
  ]
  params: {
    vnetName: vnet.outputs.name
    vnetId: vnet.outputs.id
    zoneName: 'privatelink.documents.azure.com'
    autoRegistration: false
  }
}
