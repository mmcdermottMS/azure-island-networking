param location string
param name string
param tags object

resource mi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: name
  location: location
  tags: tags
}

output principalId string = mi.properties.principalId
