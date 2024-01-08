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
param regionCode string
param timeStamp string = utcNow('yyyyMMddHHmm')
param tags object = {}

// Optional services
param deployBridge bool = false
param deployVnetGateway bool = false

var resourcePrefix = '${orgPrefix}-${appPrefix}-${regionCode}'

// DNS Server
param vmAdminUserName string = 'vmadmin'

@secure()
param vmAdminPwd string

// HUB VNET IP SETTINGS
param hubVnetAddressSpace string = '10.10.0.0/20'
param hubFirewallSubnetAddressSpace string = '10.10.0.0/25' // 123 addresses - 10.10.0.0 - 10.10.0.127
param hubDnsSubnetAddressSpace string = '10.10.0.128/25' // 123 addresses - 10.10.0.128 - 10.10.1.255
param hubDnsResolverOutboundSubnetAddressSpace string = '10.10.1.0/26' // 59 addresses - 10.10.1.0 - 10.10.1.63
param hubServicesSubnetAddressSpace string = '10.10.1.64/26' // 59 addresses - 10.10.1.64 - 10.10.1.127
param hubGatewaySubnetAddressSpace string = '10.10.1.128/26' // 59 addresses

// BRIDGE VNET IP SETTINGS
param bridgeVnetAddressSpace string = '10.10.16.0/20'
param bridgeFirewallSubnetAddressSpace string = '10.10.16.0/25' // 123 addresses - 10.10.16.0 - 10.10.16.127
param bridgeBastionSubnetAddressSpace string = '10.10.16.128/25' // 123 addresses - 10.10.16.128 - 10.10.0.255
param bridgePrivateLinkSubnetAddressSpace string = '10.10.17.0/25' // 123 addresses - 10.10.17.0 - 10.10.17.127
param bridgeAppGatewaySubnetAddressSpace string = '10.10.17.128/25' // 123 addresses - 10.10.17.128 - 10.10.17.255

// SPOKE VNET IP SETTINGS
param spokeVnetAddressSpace string = '10.10.32.0/20'
param spokeVnetVmAddressSpace string = '10.10.32.0/25' // 123 addresses - 10.10.32.0 - 10.10.32.127
param spokeVnetPrivateLinkAddressSpace string = '10.10.32.128/25' // 123 addresses - 10.10.32.128 - 10.10.32.255
param spokeVnetIntegrationSubnetAddressSpace string = '10.10.33.0/25' // 123 addresses - 10.10.33.0 - 10.10.33.127
param spokeAzureBastionSubnetAddressSpace string = '10.10.34.0/26' // 59 addresses -10.10.34.0 - 10.10.34.63

// SECOND BRIDGE VNET IP SETTINGS
param bridge02VnetAddressSpace string = '10.10.64.0/20'
param bridge02FirewallSubnetAddressSpace string = '10.10.64.0/25' // 123 addresses - 10.10.16.0 - 10.10.16.127
param bridge02BastionSubnetAddressSpace string = '10.10.64.128/25' // 123 addresses - 10.10.16.128 - 10.10.0.255
param bridge02PrivateLinkSubnetAddressSpace string = '10.10.65.0/25' // 123 addresses - 10.10.17.0 - 10.10.17.127
param bridge02AppGatewaySubnetAddressSpace string = '10.10.65.128/25' // 123 addresses - 10.10.17.128 - 10.10.17.255

// ISLAND VNET ADDRESS SPACE
param islandVnetAddressPrefix string = '192.168.0.0/16'

resource netrg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${orgPrefix}-${appPrefix}-network'
  location: region
  tags: tags
}

resource dnsrg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${orgPrefix}-${appPrefix}-dns'
  location: region
  tags: tags
}

resource utilRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${orgPrefix}-${appPrefix}-util'
  location: region
}

resource monitoringRg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: '${orgPrefix}-${appPrefix}-monitoring'
  location: region
}

module logAnalytics 'modules/logAnalytics.bicep' = {
  name: '${timeStamp}-log-analytics'
  scope: resourceGroup(monitoringRg.name)
  params: {
    location: region
    resourcePrefix: resourcePrefix
  }
}

module hubVnet 'modules/vnet.bicep' = {
  name: '${timeStamp}-hub-vnet'
  scope: resourceGroup(netrg.name)
  params: {
    vnetName: '${resourcePrefix}-hub'
    location: region
    addressSpaces: [
      hubVnetAddressSpace
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hubFirewallSubnetAddressSpace
        }
      }
      {
        name: 'dns'
        properties: {
          addressPrefix: hubDnsSubnetAddressSpace
          networkSecurityGroup: {
            id: hubDnsNsg.outputs.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'dns-resolver-outbound'
        properties: {
          addressPrefix: hubDnsResolverOutboundSubnetAddressSpace
          networkSecurityGroup: {
            id: hubDnsNsg.outputs.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'dns-resolver'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
      {
        name: 'services'
        properties: {
          addressPrefix: hubServicesSubnetAddressSpace
          networkSecurityGroup: {
            id: servicesNsg.outputs.id
          }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: hubGatewaySubnetAddressSpace
        }
      }
    ]
  }
}

module bridge01Vnet 'modules/vnet.bicep' = {
  name: '${timeStamp}-bridge01-vnet'
  scope: resourceGroup(netrg.name)
  params: {
    vnetName: '${resourcePrefix}-bridge01'
    location: region
    addressSpaces: [
      bridgeVnetAddressSpace
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: bridgeFirewallSubnetAddressSpace
          routeTable: {
            id: (deployBridge ? bridgeRoute.outputs.id : null)
          }
        }
      }
      {
        // NOTE: UDR not allowed in a Bastion subnet
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bridgeBastionSubnetAddressSpace
          networkSecurityGroup: {
            id: (deployBridge ? bastionNsg.outputs.id : '')
          }
        }
      }
      {
        name: 'privatelinks'
        properties: {
          addressPrefix: bridgePrivateLinkSubnetAddressSpace
          networkSecurityGroup: {
            id: (deployBridge ? bridgePrivateLinkNsg.outputs.id : null)
          }
        }
      }
      {
        name: 'appgateways'
        properties: {
          addressPrefix: bridgeAppGatewaySubnetAddressSpace
          networkSecurityGroup: {
            id: (deployBridge ? bridgeAppGatewayNsg.outputs.id : '')
          }
        }
      }
    ]
  }
}

module bridge02Vnet 'modules/vnet.bicep' = {
  name: '${timeStamp}-bridge02-vnet'
  scope: resourceGroup(netrg.name)
  params: {
    vnetName: '${resourcePrefix}-bridge02'
    location: region
    addressSpaces: [
      bridge02VnetAddressSpace
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: bridge02FirewallSubnetAddressSpace
          routeTable: {
            id: bridgeRoute.outputs.id
          }
        }
      }
      {
        // NOTE: UDR not allowed in a Bastion subnet
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bridge02BastionSubnetAddressSpace
          networkSecurityGroup: {
            id: bastionNsg.outputs.id
          }
        }
      }
      {
        name: 'privatelinks'
        properties: {
          addressPrefix: bridge02PrivateLinkSubnetAddressSpace
          networkSecurityGroup: {
            id: bridgePrivateLinkNsg.outputs.id
          }
        }
      }
      {
        name: 'appgateways'
        properties: {
          addressPrefix: bridge02AppGatewaySubnetAddressSpace
          networkSecurityGroup: {
            id: bridgeAppGatewayNsg.outputs.id
          }
        }
      }
    ]
  }

}

module spokeVnet 'modules/vnet.bicep' = {
  name: '${timeStamp}-spoke-vnet'
  scope: resourceGroup(netrg.name)
  params: {
    vnetName: '${resourcePrefix}-spoke'
    location: region
    addressSpaces: [
      spokeVnetAddressSpace
    ]
    subnets: [
      {
        name: 'compute'
        properties: {
          addressPrefix: spokeVnetVmAddressSpace
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: spokeVirtualMachinesNsg.outputs.id
          }
        }
      }
      {
        name: 'services'
        properties: {
          addressPrefix: spokeVnetPrivateLinkAddressSpace
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: spokePrivateLinkNsg.outputs.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'integration'
        properties: {
          addressPrefix: spokeVnetIntegrationSubnetAddressSpace
          privateEndpointNetworkPolicies: 'Enabled'
          routeTable: {
            id: route.outputs.id
          }
          networkSecurityGroup: {
            id: spokeIntegrationNsg.outputs.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: spokeAzureBastionSubnetAddressSpace
        }
        networkSecurityGroup: {
          id: bastionNsg.outputs.id
        }
      }
    ]
  }
}

// NSG for Services subnet (Private Endpoints from Islands)
module servicesNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-hub-services'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-hub-services'
    location: region
    securityRules: [] //TODO: Create NSG rules
  }
}

// NSG for DNS subnet (Linux server running BIND)
module hubDnsNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-hub-dns'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-hub-dns'
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

// NSG for Bastion subnet
module bastionNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-bridge-bastion'
  scope: resourceGroup(netrg.name)
  dependsOn: [
    hubDnsNsg
  ]
  params: {
    name: '${resourcePrefix}-bridge-bastion'
    location: region
    securityRules: [
      // SEE: https://docs.microsoft.com/en-us/azure/bastion/bastion-nsg#apply
      {
        name: 'bastion-ingress'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion-gatewaymgr'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion-loadbalancer'
        properties: {
          priority: 140
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'AllowGetSessionInformation'
        properties: {
          priority: 130
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
      {
        name: 'deny-internet'
        properties: {
          priority: 140
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// NSG for Azure services configured with Private Link (bridge)
module bridgePrivateLinkNsg 'modules/nsg.bicep' = if (deployBridge) {
  name: '${timeStamp}-bridge-privatelinks'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-bridge-privatelinks'
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
      {
        name: 'deny-internet'
        properties: {
          priority: 1000
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// NSG for App Gateway subnet (private build servers)
module bridgeAppGatewayNsg 'modules/nsg.bicep' = if (deployBridge) {
  name: '${timeStamp}-bridge-appgw'
  scope: resourceGroup(netrg.name)
  dependsOn: [
    bastionNsg
  ]
  params: {
    name: '${resourcePrefix}-bridge-appgw'
    location: region
    securityRules: [
      {
        name: 'deny-internet'
        properties: {
          priority: 1000
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// NSG for Azure Functions subnet
module spokeVirtualMachinesNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-spoke-iaas'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-spoke-iaas'
    location: region
    securityRules: [
      {
        name: 'allow-inbound-vm-admin'
        properties: {
          priority: 100
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: hubVnetAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'allow-inbound-web'
        properties: {
          priority: 110
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: hubVnetAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }

      // Internet egress will be forced through Azure Fireall. Deny at the NSG level supercedes UDR flow
    ]
  }
}

// NSG for Azure Functions subnet
module spokeIntegrationNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-spoke-integration-nsg'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-spoke-integration'
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

// NSG for Azure services configured with Private Link (spoke)
module spokePrivateLinkNsg 'modules/nsg.bicep' = {
  name: '${timeStamp}-spoke-privatelinks'
  scope: resourceGroup(netrg.name)
  dependsOn: [
    spokeIntegrationNsg
  ]
  params: {
    name: '${resourcePrefix}-spoke-privatelinks'
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
      {
        name: 'deny-internet'
        properties: {
          priority: 1000
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Azure Fireall - HUB
module hubAzFw 'modules/azfw.bicep' = {
  name: '${timeStamp}-hub-azfw'
  scope: resourceGroup(netrg.name)
  params: {
    prefix: '${resourcePrefix}-hub'
    fireWallSubnetName: 'AzureFirewallSubnet'
    location: region
    hubVnetName: hubVnet.outputs.name
    privateTrafficPrefixes: bridgeVnetAddressSpace
    networkRules: [
      {
        name: 'core-rules'
        properties: {
          action: { type: 'Allow' }
          priority: 100
          rules: [
            {
              description: 'Allow outbound web traffic'
              name: 'corp-to-internet'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                spokeVnetAddressSpace
                hubVnetAddressSpace
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '80'
                '443'
              ]
            }
            {
              description: 'Allow Island to Corp'
              name: 'bridge-to-spoke'
              protocols: [
                'TCP'
                'UDP'
              ]
              sourceAddresses: [
                bridgeVnetAddressSpace
              ]
              destinationAddresses: [
                spokeVnetAddressSpace
              ]
              destinationPorts: [
                '*'
              ]
            }
          ]
        }
      }
    ]
  }
}

// Azure Firewall - BRIDGE
module bridgeAzFw 'modules/azfw.bicep' = if (deployBridge) {
  name: '${timeStamp}-bridge01-azfw'
  scope: resourceGroup(netrg.name)
  params: {
    prefix: '${resourcePrefix}-bridge01'
    fireWallSubnetName: 'AzureFirewallSubnet'
    location: region
    hubVnetName: (deployBridge ? bridge01Vnet.outputs.name : '')
    networkRules: [
      {
        name: 'island-networking-config'
        properties: {
          action: { type: 'Allow' }
          priority: 100
          rules: [
            {
              description: 'Allow outbound web traffic'
              name: 'island-to-internet'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '80'
                '443'
              ]
            }
            {
              description: 'Allow Island to Corp'
              name: 'island-to-corp'
              protocols: [
                'TCP'
                'UDP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '10.0.0.0/8'
              ]
              destinationPorts: [
                '*'
              ]
            }
          ]
        }
      }
    ]
  }
}

//TODO: The firewall isn't quite setup right for allowing Application Insights 
//TODO - AppInsights Firewall Settings: https://learn.microsoft.com/en-us/azure/azure-monitor/app/ip-addresses

// Azure Firewall - BRIDGE 02
module bridge02AzFw 'modules/azfw.bicep' = {
  name: '${timeStamp}-bridge02-azfw'
  scope: resourceGroup(netrg.name)
  params: {
    prefix: '${resourcePrefix}-bridge02'
    fireWallSubnetName: 'AzureFirewallSubnet'
    location: region
    hubVnetName: bridge02Vnet.outputs.name
    networkRules: [
      {
        name: 'island-networking-config'
        properties: {
          action: { type: 'Allow' }
          priority: 100
          rules: [
            {
              description: 'Allow outbound web traffic'
              name: 'island-to-internet'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '80'
                '443'
              ]
            }
            {
              description: 'Allow Island to Corp'
              name: 'island-to-corp'
              protocols: [
                'TCP'
                'UDP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '10.0.0.0/8'
              ]
              destinationPorts: [
                '*'
              ]
            }
          ]
        }
      }
      {
        name: 'SpringAppsRefArchNetworkRules'
        properties: {
          action: { type: 'Allow' }
          priority: 110
          rules: [
            {
              name: 'AllowKMSActivation'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '1688'
              ]
            }
            {
              name: 'NtpQuery'
              protocols: [
                'UDP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '123'
              ]
            }
            {
              name: 'SpringMgmt'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
              destinationPorts: [
                '443'
              ]
            }
            {
              name: 'KubernetesMgmtTcp'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
              destinationPorts: [
                '9000'
              ]
            }
            {
              name: 'KubernetesMgmtUdp'
              protocols: [
                'UDP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                'AzureCloud'
              ]
              destinationPorts: [
                '1194'
              ]
            }
            {
              name: 'AzureContainerRegistery'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                'AzureContainerRegistry'
              ]
              destinationPorts: [
                '443'
              ]
            }
            {
              name: 'AzureStorage'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              destinationAddresses: [
                'Storage'
              ]
              destinationPorts: [
                '443'
              ]
            }
          ]
        }
      }
    ]
    applicationRules: [
      {
        name: 'SpringAppsApplicationRules'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 100
          rules: [
            {
              name: 'AllowAks'
              fqdnTags: [
                'AzureKubernetesService'
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
            }
            {
              name: 'AllowKubMgmt'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                '*.azmk8s.io'
                substring(environment().resourceManager, 8, length(environment().resourceManager) - 9) //This strips off the protocol and trailing slash and is to eliminate the linter failure on hard coded special domains
              ]
            }
            {
              name: 'AllowMCR'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'mcr.microsoft.com'
              ]
            }
            {
              name: 'AllowMCRStorage'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                '*.cdn.mscr.io'
                '*.data.mcr.microsoft.com'
              ]
            }
            {
              name: 'AllowAzureAd'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                substring(environment().authentication.loginEndpoint, 8, length(environment().authentication.loginEndpoint) - 9) //This strips off the protocol and trailing slash and is to eliminate the linter failure on hard coded special domains
              ]
            }
            {
              name: 'AllowMSPackRepo'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'packages.microsoft.com'
                'acs-mirror.azureedge.net'
                '*.azureedge.net'
              ]
            }
            {
              name: 'AllowGitHub'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'github.com'
              ]
            }
            {
              name: 'AllowDocker'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                '*.docker.io'
                '*.docker.com'
              ]
            }
            {
              name: 'AllowSnapcraft'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'api.snapcraft.io'
              ]
            }
            {
              name: 'AllowClamAv'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'database.clamav.net'
              ]
            }
            {
              name: 'Allow*UbuntuMisc'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'motd.ubuntu.com'
              ]
            }
            {
              name: 'MsCrls'
              protocols: [
                {
                  port: 80
                  protocolType: 'Http'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'crl.microsoft.com'
                'mscrl.microsoft.com'
              ]
            }
            {
              name: 'AllowDigiCerty'
              protocols: [
                {
                  port: 80
                  protocolType: 'Http'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'crl3.digicert.com'
                'crl4.digicert.com'
              ]
            }
          ]
        }
      }
      {
        name: 'AllowAcmeFitnessInstall'
        properties: {
          action: {
            type: 'Allow'
          }
          priority: 800
          rules: [
            {
              name: 'nuget'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'api.nuget.org'
              ]
            }
            {
              name: 'pypi'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'pypi.org'
                'files.pythonhosted.org'
              ]
            }
            {
              name: 'npm'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'registry.npmjs.org'
              ]
            }
            {
              name: 'gradle'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'services.gradle.org'
                'downloads.gradle-dn.com'
                'plugins.gradle.org'
                'plugins-artifacts.gradle.org'
                'repo.gradle.org'
              ]
            }
            {
              name: 'maven'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }
              ]
              sourceAddresses: [
                islandVnetAddressPrefix
              ]
              targetFqdns: [
                'repo.maven.apache.org'
              ]
            }
          ]
        }
      }
    ]
  }
}

// VNET peering
module HubToSpokePeering 'modules/peering.bicep' = {
  name: '${timeStamp}-hub-to-spoke-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: hubVnet.outputs.name
    remoteVnetName: 'spoke'
    remoteVnetId: spokeVnet.outputs.id
  }
}

// VNET peering
module SpokeToHubPeering 'modules/peering.bicep' = {
  name: '${timeStamp}-spoke-to-hub-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: spokeVnet.outputs.name
    remoteVnetName: 'hub'
    remoteVnetId: hubVnet.outputs.id
  }
}

module HubToBridgePeering 'modules/peering.bicep' = if (deployBridge) {
  name: '${timeStamp}-hub-to-bridge01-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: hubVnet.outputs.name
    remoteVnetName: 'bridge01'
    remoteVnetId: (deployBridge ? bridge01Vnet.outputs.id : '')
  }
}

module BridgeToHubPeering 'modules/peering.bicep' = if (deployBridge) {
  name: '${timeStamp}-bridge01-to-hub-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: (deployBridge ? bridge01Vnet.outputs.name : '')
    remoteVnetName: 'hub'
    remoteVnetId: hubVnet.outputs.id
  }
}

module HubTobridge02Peering 'modules/peering.bicep' = {
  name: '${timeStamp}-hub-to-bridge02-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: hubVnet.outputs.name
    remoteVnetName: 'bridge02'
    remoteVnetId: bridge02Vnet.outputs.id
  }
}

module bridge02ToHubPeering 'modules/peering.bicep' = {
  name: '${timeStamp}-bridge02-to-hub-peering'
  scope: resourceGroup(netrg.name)
  params: {
    localVnetName: (deployBridge ? bridge02Vnet.outputs.name : '')
    remoteVnetName: 'hub'
    remoteVnetId: hubVnet.outputs.id
  }
}

// User Defined Route (force egress traffic through hub firewall)
module route 'modules/udr.bicep' = {
  name: '${timeStamp}-core-udr'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-egress-udr'
    location: region
    routes: [
      {
        name: 'InternetRoute'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: hubAzFw.outputs.privateIp
        }
      }
    ]
  }
}

// Force bridge traffic to the hub AZ FW private interface
module bridgeRoute 'modules/udr.bicep' = if (deployBridge) {
  name: '${timeStamp}-bridge-udr'
  scope: resourceGroup(netrg.name)
  params: {
    name: '${resourcePrefix}-bridge-udr'
    location: region
    routes: [
      {
        name: 'island-to-internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
      {
        name: 'island-to-corp-network'
        properties: {
          addressPrefix: spokeVnetAddressSpace
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: hubAzFw.outputs.privateIp
        }
      }
    ]
  }
}

// Bastion
module bastion 'modules/bastion.bicep' = {
  name: 'bridge-bastion'
  scope: resourceGroup(netrg.name)
  params: {
    prefix: resourcePrefix
    location: region
    subnetId: '${spokeVnet.outputs.id}/subnets/AzureBastionSubnet'
    sku: 'Basic'
  }
}

// Private DNS zone for Azure Web Sites (Functions and Web Apps)
module privateZoneAzureWebsites 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-azurewebsites'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink.azurewebsites.net'
  }
}

// Link the spoke VNet to the privatelink.azurewebsites.net private zone
module spokeVnetAzureWebsitesZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-azurewebsites-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureWebsites
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink.azurewebsites.net'
    autoRegistration: false
  }
}

// Link the hub VNet to the privatelink.azurewebsites.net private zone
module hubVnetAzureWebsitesZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-azurewebsites-hubvnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureWebsites
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink.azurewebsites.net'
    autoRegistration: false
  }
}

// Private DNS zone for Azure Blob Storage (ADLS)
module privateZoneAzureBlobStorage 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-storage-blob'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
}

// Link the spoke VNet to the privatelink.blob.core.windows.net private zone
module spokeVnetAzureBlobStorageZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-blobstorage-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureBlobStorage
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink.blob.${environment().suffixes.storage}'
    autoRegistration: false
  }
}

// Link the hub VNet to the privatelink.blob.core.windows.net private zone
module hubVnetAzureBlobStorageZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-blobstorage-hubvnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureBlobStorage
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink.blob.${environment().suffixes.storage}'
    autoRegistration: false
  }
}

// Private DNS for Azure Data Factory
module privateZoneAzureDataFactory 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-datafactory'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink.datafactory.azure.net'
  }
}

// Link the spoke VNet to the privatelink.datafactory.azure.net private zone
module spokeVnetAzureDataFactoryZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-datafactory-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureDataFactory
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink.datafactory.azure.net'
    autoRegistration: false
  }
}

// Link the hub VNet to the privatelink.datafactory.azure.net private zone
module hubVnetAzureDataFactoryZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-datafactory-hubvnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzureDataFactory
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink.datafactory.azure.net'
    autoRegistration: false
  }
}

// Private DNS zone for SQL
module privateZoneSql 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-sql'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink${environment().suffixes.sqlServerHostname}'
  }
}

// Link the spoke VNet to the privatelink.database.windows.net private zone
module spokeVnetSqlZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-sql-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneSql
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink${environment().suffixes.sqlServerHostname}'
    autoRegistration: false
  }
}

// Link the hub VNet to the privatelink.database.windows.net private zone
module hubVnetSqlZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-sql-hubvnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneSql
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink${environment().suffixes.sqlServerHostname}'
    autoRegistration: false
  }
}

module privateZoneKeyVault 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-keyvault'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink.vaultcore.azure.net'
  }
}

module spokeVnetKeyVaultZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-keyvault-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneKeyVault
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink.vaultcore.azure.net'
    autoRegistration: false
  }
}

module hubVnetKeyVaultZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-keyvault-hubvnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneKeyVault
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink.vaultcore.azure.net'
    autoRegistration: false
  }
}

// Private DNS zone for other Azure services
module privateZoneAzure 'modules/dnsPrivateZone.bicep' = {
  name: '${timeStamp}-dns-private-azure'
  scope: resourceGroup(dnsrg.name)
  params: {
    zoneName: 'privatelink.azure.com'
  }
}

// Link the spoke VNet to the privatelink.azure.com private zone
// NOTE: See: https://learn.microsoft.com/en-us/azure/bastion/bastion-faq#my-privatelinkazurecom-cant-resolve-to-managementprivatelinkazurecom
// Must add CNAME record for 'management.privatelink.azure.com' that points to 'arm-frontdoor-prod.trafficmanager.net'
module frontdoorcname 'modules/dnscname.bicep' = {
  name: '${timeStamp}-frontdoor-cname'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzure
  ]
  params: {
    appName: 'management'
    dnsZone: 'privatelink.azure.com'
    #disable-next-line no-hardcoded-env-urls
    alias: 'arm-frontdoor-prod.trafficmanager.net'
  }
}

module spokeVnetAzureZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-azure-spokevnet'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzure
  ]
  params: {
    vnetName: spokeVnet.outputs.name
    vnetId: spokeVnet.outputs.id
    zoneName: 'privatelink.azure.com'
    autoRegistration: false
  }
}

module hubVnetAzureZoneLink 'modules/dnszonelink.bicep' = {
  name: '${timeStamp}-dns-link-azure-hub'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    privateZoneAzure
  ]
  params: {
    vnetName: hubVnet.outputs.name
    vnetId: hubVnet.outputs.id
    zoneName: 'privatelink.azure.com'
    autoRegistration: false
  }
}

// HACK: THIS IS A HACK - need to find a better way to apply the UDR to the DNS server subnet
module applyHubRoutes 'modules/vnet.bicep' = {
  name: '${timeStamp}-hub-vnet-update'
  scope: resourceGroup(netrg.name)
  params: {
    vnetName: '${resourcePrefix}-hub'
    location: region
    addressSpaces: [
      hubVnetAddressSpace
    ]
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hubFirewallSubnetAddressSpace
        }
      }
      {
        name: 'dns'
        properties: {
          addressPrefix: hubDnsSubnetAddressSpace
          networkSecurityGroup: {
            id: hubDnsNsg.outputs.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          routeTable: {
            id: route.outputs.id
          }
        }
      }
      {
        name: 'dns-resolver-outbound'
        properties: {
          addressPrefix: hubDnsResolverOutboundSubnetAddressSpace
          networkSecurityGroup: {
            id: hubDnsNsg.outputs.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'dns-resolver'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
      {
        name: 'services'
        properties: {
          addressPrefix: hubServicesSubnetAddressSpace
          networkSecurityGroup: {
            id: servicesNsg.outputs.id
          }
        }
      }
    ]
  }
}

// Public IP for the VNET Gateway
module vnetGatewayPublicIp 'modules/publicIpAddress.bicep' = if (deployVnetGateway) {
  name: 'vnet-gateway-pip'
  scope: resourceGroup(netrg.name)
  params: {
    resourceName: '${resourcePrefix}-vnet-gateway-pip'
    location: region
    publicIpAddressSku: 'Standard'
    publicIpAddressType: 'Static'
  }
}

// VNET Gateway
module vnetGateway 'modules/vnetGateway.bicep' = if (deployVnetGateway) {
  name: 'vnet-gateway'
  scope: resourceGroup(netrg.name)
  dependsOn: [
    hubVnet
  ]
  params: {
    name: '${resourcePrefix}-vnet-gateway'
    location: region
    subnetId: '${hubVnet.outputs.id}/subnets/GatewaySubnet'
  }
}

// DNS server for contoso.com
module dnsServer 'modules/virtualMachine.bicep' = {
  name: '${timeStamp}-dns-server-consoso-com'
  scope: resourceGroup(utilRg.name)
  dependsOn: [
    applyHubRoutes
  ]
  params: {
    adminUserName: vmAdminUserName
    adminPassword: vmAdminPwd
    networkResourceGroupName: netrg.name
    location: region
    vnetName: hubVnet.outputs.name
    subnetName: 'dns'
    os: 'linux'
    vmName: '${resourcePrefix}-dns01'
    vmSize: 'Standard_B2as_v2'
    initScriptBase64: loadFileAsBase64('dnsserver.yml')
  }
}

// Private DNS Resolver
module dnsResolver 'modules/dnsResolver.bicep' = {
  name: '${timeStamp}-dns-resolver'
  scope: resourceGroup(dnsrg.name)
  dependsOn: [
    applyHubRoutes
  ]
  params: {
    name: '${resourcePrefix}-dnsresolver-hub'
    location: region
    vnetId: hubVnet.outputs.id
    vnetName: hubVnet.outputs.name
    resourceGroupNameNetwork: netrg.name
    outboundEndpointName: 'dns-resolver-hub-outbound'
    outboundSubnetName: 'dns-resolver-outbound'
  }
}

// Forwarding ruleset for contoso.com
module contosoForwardingRuleset 'modules/dnsForwardingRuleset.bicep' = {
  name: '${timeStamp}-dns-forward-ruleset-core'
  scope: resourceGroup(dnsrg.name)
  params: {
    name: 'dns-forward-ruleset-contoso'
    location: region
    outEndpointId: dnsResolver.outputs.outboundEndpointId
    forwardingRuleName: 'contoso-com'
    forwardinRuleDomainName: 'contoso.com.'
    forwardingRuleTargetDnsServers: [
      {
        ipAddress: dnsServer.outputs.privateIPAddress
        port: 53
      }
    ]
  }
}

// Link to Hub VNET to the Private DNS resolver
module resolverLinkHub 'modules/dnsResolverLink.bicep' = {
  name: '${timeStamp}-dns-resolver-link-hub'
  scope: resourceGroup(dnsrg.name)
  params: {
    forwardingRulesetName: contosoForwardingRuleset.outputs.ruleSetName
    linkName: '${hubVnet.outputs.name}-link'
    vnetId: hubVnet.outputs.id
  }
}

// Link to spoke VNET to the Private DNS resolver
module resolverLinkSpoke 'modules/dnsResolverLink.bicep' = {
  name: '${timeStamp}-dns-resolver-link-spoke'
  scope: resourceGroup(dnsrg.name)
  params: {
    forwardingRulesetName: contosoForwardingRuleset.outputs.ruleSetName
    linkName: '${spokeVnet.outputs.name}-link'
    vnetId: spokeVnet.outputs.id
  }
}

// Test web server hosting http://api.contoso.com
module webServer 'modules/virtualMachine.bicep' = {
  name: '${timeStamp}-web-server-consoso-com'
  scope: resourceGroup(utilRg.name)
  params: {
    adminUserName: vmAdminUserName
    adminPassword: vmAdminPwd
    networkResourceGroupName: netrg.name
    location: region
    vnetName: spokeVnet.outputs.name
    subnetName: 'compute'
    os: 'linux'
    vmName: '${resourcePrefix}-web01'
    vmSize: 'Standard_B2as_v2'
    initScriptBase64: loadFileAsBase64('webserver.yml')
  }
}
