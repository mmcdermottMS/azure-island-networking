Function DecoratedOutput {
    param(
        [Parameter (Mandatory = $true)] [String]$baseMessage,
        [Parameter (Mandatory = $false)] [String]$secondaryMessage
    )

    Write-Host "$(Get-Date -Format G): " -ForegroundColor Yellow -NoNewline

    if ($secondaryMessage) {
        Write-Host "$baseMessage " -NoNewLine
        Write-Host "$secondaryMessage" -ForegroundColor Green
    }
    else {
        Write-Host "$baseMessage"
    }    
}

$timeStamp = Get-Date -Format "yyyyMMddHHmm"
$location = $Args[0]
$orgPrefix = $Args[1]
$appPrefix = $Args[2]
$subscriptionId = $Args[3]
$targetResourceGroup = "$orgPrefix-$appPrefix-workload"

switch ($location) {
    'eastus' {
        $regionCode = 'eus'
    }
    'eastus2' {
        $regionCode = 'eus2'
    }
    'centralus' {
        $regionCode = 'cus'
    }
    'westus' {
        $regionCode = 'wus'
    }
    'westus2' {
        $regionCode = 'wus2'
    }
    'westus3' {
        $regionCode = 'wus3'
    }
    'northcentralus' {
        $regionCode = 'ncus'
    }

    Default {
        throw "Invalid Target Location Specified"
    }
}


# Define variables for configuration and managed identity assignment
$appName = "$orgPrefix-$appPrefix"
$serviceBusName = "$appName-$regionCode-sbns"
$eventHubName = "$appName-$regionCode-ehns"
$cosmosAccountName = "$appName-$regionCode-acdb"
$aksName = "$appName-$regionCode-aks"
$containerRegistryName = $appName.ToString().ToLower().Replace("-", "") + "$regionCode" + "acr"
$kvName = "$appName-$regionCode-kv"
$acrPullIdentityName = "$appName-$regionCode-mi-acrPull"
$kvSecretsUserIdentityName = "$appName-$regionCode-mi-kvSecrets"

# Create a user defined managed identity and assign the AcrPull role to it.  This identity will then be added to all the function apps so they can access the container registry via managed identity
$acrPullPrincipalId = (az identity create --name $acrPullIdentityName --resource-group $targetResourceGroup --location $location --query principalId --output tsv)
$acrPullRoleId = (az role definition list --name "AcrPull" --query [0].id --output tsv)
DecoratedOutput "Got AcrPull Role Id:" $acrPullRoleId
$acrPullRoleAssignment_output = (az role assignment create --assignee $acrPullPrincipalId --role $acrPullRoleId --scope "/subscriptions/$subscriptionId/resourcegroups/$targetResourceGroup/providers/Microsoft.ContainerRegistry/registries/$containerRegistryName" --output tsv)
DecoratedOutput "Completed role assignment of acrPull to User Identity"

# Create a user defined managed identity and assign the Key Vault Secrets User role to it.  This identity will then be added to all the function apps so they can access Key Vault via managed identity
$kvSecretsPrincipalId = (az identity create --name $kvSecretsUserIdentityName --resource-group $targetResourceGroup --location $location --query principalId --output tsv)
$keyVaultSecretsRoleId = (az role definition list --name "Key Vault Secrets User" --query [0].id --output tsv)
DecoratedOutput "Got Key Vault Secrets User Role Id:" $keyVaultSecretsRoleId
$kvSecretRoleAssignment_output = (az role assignment create --assignee $kvSecretsPrincipalId --role $keyVaultSecretsRoleId --scope "/subscriptions/$subscriptionId/resourcegroups/$targetResourceGroup/providers/Microsoft.KeyVault/vaults/$kvName" --output tsv)
DecoratedOutput "Completed role assignment of Key Vault Secrets User to User Identity"

# Wire up ACR to AKS - TODO: UNCOMMENT THIS ONCE AKS IS PROVISIONED
#$aksUpdate_output = az aks update -n $aksName -g $targetResourceGroup --attach-acr $containerRegistryName
#DecoratedOutput "Wired up AKS to ACR"
