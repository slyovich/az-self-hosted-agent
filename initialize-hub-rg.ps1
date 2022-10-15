# Script to initialize our landing zone to support:
# - Azure DevOps secured deployment (self-hosted agent)
# - Terraform storage account
# - Hub virtual network
# - Central Log Analytics Workspace
# - Central Key Vault

param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$logAnalyticsWorkspaceName,
    [string]$keyVaultName,
    [string]$acrName,
    [string]$storageAccountName,
    [string]$vnetName,
    [string]$vnetAddresses,
    [string]$privateEndpointSubnetAddresses,
    [string]$selfHostedSubnetAddresses,
    [string]$nsgName,
    [string]$appServicePlanName,
    [string]$appName,
    [string]$containerAppEnvironmentName,
    [string]$containerAppName,
    [string]$AZP_POOL,
    [string]$AZP_AGENT_NAME,
    [string]$AZP_URL,
    [string]$AZP_TOKEN,
    [switch]$appServiceSelftHostedAgent,
    [System.Collections.ArrayList]$additionalDnsZones   #Additional DNS Zones needed, except "privatelink.vaultcore.azure.net" and "privatelink.azurewebsites.net"
)

$sciptFolder = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

$commonTags = "description=az-hub-landing-zone"

# Get current logged in user
$currentUserId = $(az account show --output tsv --query "user.name")

#allow installing extensions without prompt
az config set extension.use_dynamic_install=yes_without_prompt

# Create resource group to store our es default infrastructure
az group create --name $resourceGroupName --location $location --tags $commonTags

# Create log analytics workspace
az monitor log-analytics workspace create --workspace-name $logAnalyticsWorkspaceName --resource-group $resourceGroupName --location $location --tags $commonTags
$logAnalyticsWorkspaceCustomerId = $(az monitor log-analytics workspace show --workspace-name $logAnalyticsWorkspaceName --resource-group $resourceGroupName --query "customerId" --output tsv)
$logAnalyticsWorkspaceKey = $(az monitor log-analytics workspace get-shared-keys --workspace-name $logAnalyticsWorkspaceName --resource-group $resourceGroupName --query "primarySharedKey" --output tsv)

# Create Terraform backend storage
& "$($sciptFolder)\modules\tfstorage.ps1" `
    -resourceGroupName $resourceGroupName -location $location `
    -storageAccountName $storageAccountName `
    -commonTags $commonTags

# Create Azure Container Registry
& "$($sciptFolder)\modules\acr.ps1" `
    -resourceGroupName $resourceGroupName -location $location `
    -logAnalyticsWorkspaceName $logAnalyticsWorkspaceName `
    -acrName $acrName `
    -currentUserId $currentUserId `
    -commonTags $commonTags

# Create Hub Virtual Network
& "$($sciptFolder)\modules\network.ps1" `
    -resourceGroupName $resourceGroupName -location $location `
    -vnetName $vnetName -vnetAddresses $vnetAddresses `
    -privateEndpointSubnetAddresses $privateEndpointSubnetAddresses -selfHostedSubnetAddresses $selfHostedSubnetAddresses `
    -nsgName $nsgName `
    -appServiceSelftHostedAgent $appServiceSelftHostedAgent `
    -commonTags $commonTags

$selfHostedSubNetId=$(az network vnet subnet show --resource-group $resourceGroupName --vnet-name $vnetName --name "SelfHostedSubNet" --query "id" --output tsv)

if ($appServiceSelftHostedAgent) {
    # Create Key Vault
    & "$($sciptFolder)\modules\keyvault.ps1" `
        -resourceGroupName $resourceGroupName -location $location `
        -keyVaultName $keyVaultName -logAnalyticsWorkspaceName $logAnalyticsWorkspaceName `
        -vnetName $vnetName `
        -currentUserId $currentUserId `
        -AZP_TOKEN $AZP_TOKEN `
        -commonTags $commonTags

    # Create Web App for containers self-hosted agent
    & "$($sciptFolder)\modules\webapp-agent.ps1" `
        -resourceGroupName $resourceGroupName -location $location `
        -keyVaultName $keyVaultName -acrName $acrName -vnetName $vnetName `
        -appServicePlanName $appServicePlanName -appName $appName `
        -AZP_POOL $AZP_POOL -AZP_AGENT_NAME $AZP_AGENT_NAME -AZP_URL $AZP_URL `
        -commonTags $commonTags
} else {
    $ "$(scriptFolder)\modules\containerapp-agent.ps1" `
        -resourceGroupName $resourceGroupName -location $location `
        -acrName $acrName -selfHostedSubNetId $selfHostedSubNetId `
        -containerAppEnvironmentName $containerAppEnvironmentName -containerAppName $containerAppName `
        -logAnalyticsWorkspaceCustomerId $logAnalyticsWorkspaceCustomerId -logAnalyticsWorkspaceKey $logAnalyticsWorkspaceKey `
        -AZP_POOL $AZP_POOL -AZP_AGENT_NAME $AZP_AGENT_NAME -AZP_URL $AZP_URL -AZP_TOKEN $AZP_TOKEN `
        -commonTags $commonTags
}

# Add additional DNS Zones
foreach ($dnsZone in $additionalDnsZones) {
    az network private-dns zone create --resource-group $resourceGroupName --name $dnsZone --tags $commonTags

    az network private-dns link vnet create --zone-name $dnsZone --resource-group $resourceGroupName `
                                            --name "PrivateLink" --registration-enabled false --virtual-network $vnetName
}

# Add locking to avoid droping unexpectingly
az group lock create --resource-group $resourceGroupName --name 'Enterprise-Scale lock' --lock-type CanNotDelete