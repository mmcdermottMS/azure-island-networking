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
$subscriptionId = $Args[0]
$location = $Args[1]
$orgPrefix = $Args[2]
$firstAppPrefix = $Args[3]
$secondAppPrefix = $Args[4]
$thirdAppPrefix = $Args[5]


if ($Args.Length -lt 4) {
    Write-Warning "Usage: deploy-all.ps1 {subscriptionId} {location} {orgPrefix} {firstWorkloadPrefix} [optional]{secondWorkloadPrefix} [optional]{thirdWorkloadPrefix}"
    exit
}

$targetResourceGroup = "$orgPrefix-$firstAppPrefix-workload"

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

DecoratedOutput "Deploying Core..."
$core_output = az deployment sub create --name "$timeStamp-core" --location $location --template-file core.bicep --parameters core.params.json region=$location orgPrefix=$orgPrefix appPrefix='core' regionCode=$regionCode
DecoratedOutput "Core Deployed."

DecoratedOutput "Deploying App Base for First Workload..."
$appbase_output = az deployment sub create --name "$timeStamp-appbase" --location $location --template-file application-base.bicep --parameters application-base.params.json region=$location orgPrefix=$orgPrefix appPrefix=$firstAppPrefix regionCode=$regionCode corePrefix='core'
DecoratedOutput "App Base for First Workload Deployed."

DecoratedOutput "Setting Target Resource Group to" $targetResourceGroup
$defaultGroup_output = az configure --defaults group="$targetResourceGroup"

DecoratedOutput "Deploying First Workload..."
$appsvc_output = az deployment group create --name "$timeStamp-appsvc" --template-file application-services.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$firstAppPrefix regionCode=$regionCode
DecoratedOutput "First Workload Deployed."

$functionApps = @(
    [PSCustomObject]@{
        AppNameSuffix     = 'fa-ehConsumer';
        StorageNameSuffix = 'ehconsumer';
    }
    [PSCustomObject]@{
        AppNameSuffix     = 'fa-sbConsumer';
        StorageNameSuffix = 'sbconsumer';
    }
    [PSCustomObject]@{
        AppNameSuffix     = 'fa-ehProducer';
        StorageNameSuffix = 'ehproducer';
    }
)

# Define variables for configuration and managed identity assignment
$appName = "$orgPrefix-$firstAppPrefix"
$serviceBusName = "$appName-$regionCode-sbns"
$eventHubName = "$appName-$regionCode-ehns"
$cosmosAccountName = "$appName-$regionCode-acdb"

# See if we already have our custom CosmosDB role defition.  This will be used for managed identity access
$cosmosRoleId = ''
(az cosmosdb sql role definition list --resource-group $targetResourceGroup --account-name $cosmosAccountName) | ConvertFrom-Json | ForEach-Object {
    #This role name is defined in the cosmos.role.definition.json file, if you change it here, change it there as well
    if ('ReadWriteRole' -eq $_.roleName) {
        $cosmosRoleId = $_.id
    }
}

# If the custom role definition doesn't exist, create it
if ([string]::IsNullOrWhiteSpace($cosmosRoleId)) {
    $cosmosRoleId = (az cosmosdb sql role definition create --resource-group $targetResourceGroup --account-name $cosmosAccountName --body "@cosmos.role.definition.json" --query id --output tsv)
    DecoratedOutput "Created Custom Cosmos Read/Write Role"
}
else {
    DecoratedOutput "Custom Cosmos Read/Write Role already exists"
}

# For each of the function apps we created...
$functionApps | ForEach-Object {
    $functionAppNameSuffix = $_.AppNameSuffix
    $storageAccountSuffix = $_.StorageNameSuffix
    $storageAccountPrefix = $appName.ToString().ToLower().Replace("-", "")
    $storageAccountName = ($storageAccountPrefix + $regionCode + "sa" + $storageAccountSuffix)
    
    # This is here to make sure we don't exceed the storage account name length restriction
    if ($storageAccountName.Length -gt 24) {
        $storageAccountName = $storageAccountName.Substring(0, 24)
    }

    # Get the system managed identity for the function app.  This will be used to access tje storage accounts via managed identity
    $functionAppIdentityId = (az functionapp identity show --resource-group $targetResourceGroup --name "$appName-$regionCode-$functionAppNameSuffix" --query principalId --output tsv)
    DecoratedOutput "Got $functionAppNameSuffix identity:" $functionAppIdentityId

    # Assign function app's system identity to the service bus data owner role
    # The owner role needs to be assigned to the listener (instead of the receiver role) so that it can peek into the queue 
    # length for making scaling decisions
    $serviceBusDataSenderRoleId = (az role definition list --name "Azure Service Bus Data Owner" --query [0].id --output tsv)
    DecoratedOutput "Got Service Bus Data Sender Role Id:" $serviceBusDataSenderRoleId
    $serviceBusRoleAssignment_output = az role assignment create --assignee $functionAppIdentityId --role $serviceBusDataSenderRoleId --scope "/subscriptions/$subscriptionId/resourcegroups/$targetResourceGroup/providers/Microsoft.ServiceBus/namespaces/$serviceBusName"
    DecoratedOutput "Completed sender role assignment of $functionAppNameSuffix to" $serviceBusName

    # Assign function app's system identity to the event hub data sender role
    $eventHubDataSenderRoleId = (az role definition list --name "Azure Event Hubs Data Sender" --query [0].id --output tsv)
    DecoratedOutput "Got Event Hub Data Sender Role Id:" $eventHubDataSenderRoleId
    $eventHubDataSenderRoleAssignment_output = az role assignment create --assignee $functionAppIdentityId --role $eventHubDataSenderRoleId --scope "/subscriptions/$subscriptionId/resourcegroups/$targetResourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubName"
    DecoratedOutput "Completed Event Hub Sender role assignment of $functionAppNameSuffix to" $eventHubName

    # Assign function app's system identity to the service bus data receiver role
    $eventHubDataReceiverRoleId = (az role definition list --name "Azure Event Hubs Data Receiver" --query [0].id --output tsv)
    DecoratedOutput "Got Event Hub Data Receiver Role Id:" $eventHubDataReceiverRoleId
    $eventHubDataReceiverRoleAssignment_output = az role assignment create --assignee $functionAppIdentityId --role $eventHubDataReceiverRoleId --scope "/subscriptions/$subscriptionId/resourcegroups/$targetResourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubName"
    DecoratedOutput "Completed Event Hub Receiver role assignment of $functionAppNameSuffix to" $eventHubName
    
    # Assign function app's system identity to the custom ComsosDB role that was created above
    $cosmosRoleAssiment_output = az cosmosdb sql role assignment create --account-name $cosmosAccountName --resource-group $targetResourceGroup --scope "/" --principal-id $functionAppIdentityId --role-definition-id $cosmosRoleId
    DecoratedOutput "Assigned Custom Cosmos Role to" $functionAppNameSuffix
}

if ($Args.Length -ge 5) {
    $appName = "$orgPrefix-$secondAppPrefix"
    $aksName = "$appName-$regionCode-aks"
    $containerRegistryName = $appName.ToString().ToLower().Replace("-", "") + "$regionCode" + "acr"

    DecoratedOutput "Deploying App Base for Second Workload..."
    $appbase_output = az deployment sub create --name "$timeStamp-appbase-2" --location $location --template-file application-base-2.bicep --parameters application-base.params.json region=$location orgPrefix=$orgPrefix appPrefix=$secondAppPrefix regionCode=$regionCode corePrefix='core'
    DecoratedOutput "App Base for Second Workload Deployed."

    $targetResourceGroup = "$orgPrefix-$secondAppPrefix-workload"
    DecoratedOutput "Setting Target Resource Group to" $targetResourceGroup
    $defaultGroup_output = az configure --defaults group="$targetResourceGroup"

    DecoratedOutput "Deploying Second Workload..."
    $appsvc_output = az deployment group create --name "$timeStamp-appsvc-2" --template-file application-services-2.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$secondAppPrefix regionCode=$regionCode
    DecoratedOutput "Second Workload Deployed."

    # Wire up ACR to AKS
    $aksUpdate_output = az aks update -n $aksName -g $targetResourceGroup --attach-acr $containerRegistryName
    DecoratedOutput "Wired up AKS to ACR"
}

if ($Args.Length -ge 6) {
    $appName = "$orgPrefix-$thirdAppPrefix"
    $aksName = "$appName-$regionCode-aks"
    $containerRegistryName = $appName.ToString().ToLower().Replace("-", "") + "$regionCode" + "acr"

    DecoratedOutput "Deploying App Base for Third Workload..."
    $appbase_output = az deployment sub create --name "$timeStamp-appbase-3" --location $location --template-file application-base-3.bicep --parameters application-base.params.json region=$location orgPrefix=$orgPrefix appPrefix=$thirdAppPrefix regionCode=$regionCode corePrefix='core'
    DecoratedOutput "App Base for Third Workload Deployed."

    $targetResourceGroup = "$orgPrefix-$ThirdAppPrefix-workload"
    DecoratedOutput "Setting Target Resource Group to" $targetResourceGroup
    $defaultGroup_output = az configure --defaults group="$targetResourceGroup"

    DecoratedOutput "Deploying Third Workload..."
    $appsvc_output = az deployment group create --name "$timeStamp-appsvc-3" --template-file application-services-3.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$thirdAppPrefix regionCode=$regionCode
    DecoratedOutput "Third Workload Deployed."

    # Wire up ACR to AKS
    $aksUpdate_output = az aks update -n $aksName -g $targetResourceGroup --attach-acr $containerRegistryName
    DecoratedOutput "Wired up AKS to ACR"
}