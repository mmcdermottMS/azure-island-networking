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
$firstAppPrefix = $Args[2]
$secondAppPrefix = $Args[3]
$thirdAppPrefix = $Args[4]


if ($Args.Length -lt 3) {
    Write-Warning "Usage: deploy-all.ps1 {location} {orgPrefix} {firstWorkloadPrefix} [optional]{secondWorkloadPrefix} [optional]{thirdWorkloadPrefix}"
    exit
}

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

$targetResourceGroup = "$orgPrefix-$firstAppPrefix-workload"
DecoratedOutput "Setting Target Resource Group to" $targetResourceGroup
$defaultGroup_output = az configure --defaults group="$targetResourceGroup"

DecoratedOutput "Deploying First Workload..."
$appsvc_output = az deployment group create --name "$timeStamp-appsvc" --template-file application-services.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$firstAppPrefix regionCode=$regionCode corePrefix='core'
DecoratedOutput "First Workload Deployed."

if ($Args.Length -ge 4) {
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
    $appsvc_output = az deployment group create --name "$timeStamp-appsvc-2" --template-file application-services-2.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$secondAppPrefix regionCode=$regionCode corePrefix='core'
    DecoratedOutput "Second Workload Deployed."

    # Wire up ACR to AKS
    $aksUpdate_output = az aks update -n $aksName -g $targetResourceGroup --attach-acr $containerRegistryName
    DecoratedOutput "Wired up AKS to ACR"
}

if ($Args.Length -ge 5) {
    DecoratedOutput "Deploying App Base for Third Workload..."
    $appbase_output = az deployment sub create --name "$timeStamp-appbase-3" --location $location --template-file application-base-3.bicep --parameters application-base.params.json region=$location orgPrefix=$orgPrefix appPrefix=$thirdAppPrefix regionCode=$regionCode corePrefix='core'
    DecoratedOutput "App Base for Third Workload Deployed."

    $targetResourceGroup = "$orgPrefix-$ThirdAppPrefix-workload"
    DecoratedOutput "Setting Target Resource Group to" $targetResourceGroup
    $defaultGroup_output = az configure --defaults group="$targetResourceGroup"

    DecoratedOutput "Deploying Third Workload..."
    $appsvc_output = az deployment group create --name "$timeStamp-appsvc-3" --template-file application-services-3.bicep --parameters application-services.params.json orgPrefix=$orgPrefix appPrefix=$thirdAppPrefix regionCode=$regionCode corePrefix='core'
    DecoratedOutput "Third Workload Deployed."
}