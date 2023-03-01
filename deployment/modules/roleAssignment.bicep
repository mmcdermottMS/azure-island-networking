param principalId string

resource udrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${principalId}', '4d97b98b-1d4f-4787-a291-c67834d212e7', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    principalId: principalId
  }
}
