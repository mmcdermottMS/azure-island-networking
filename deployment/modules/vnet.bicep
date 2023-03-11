param addressSpaces array
param isForSpringApps bool = false
param location string
param subnets array
param vnetName string

resource vnet 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressSpaces
    }
    subnets: subnets
  }
}

var roleDefinitionID = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var roleAssignmentName= guid(vnet.name, roleDefinitionID, resourceGroup().id)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01'= if(isForSpringApps) {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionID)
    principalId: 'e8de9221-a19c-4c81-b814-fd37c6caf9d2'
  }
  scope: vnet
}

output name string = vnet.name
output id string = vnet.id
