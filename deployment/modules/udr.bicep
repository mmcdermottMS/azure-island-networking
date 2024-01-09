param name string
param routes array
param location string = resourceGroup().location

resource route 'Microsoft.Network/routeTables@2022-09-01' = {
  name: name
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: routes
  }
}

output id string = route.id
