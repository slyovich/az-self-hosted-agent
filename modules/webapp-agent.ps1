param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$keyVaultName,
    [string]$acrName,
    [string]$vnetName,
    [string]$appServicePlanName,
    [string]$appName,
    [string]$AZP_POOL,
    [string]$AZP_AGENT_NAME,
    [string]$AZP_URL,
    [string]$commonTags
)

# Add private App Service used as DevOps self-hosted agent
# Create App Service Plan
$sku = "B1"         # Basic SKU supports both vnet integration and private endpoint
az appservice plan create --name $appServicePlanName --resource-group $resourceGroupName --sku $sku --location $location --is-linux --tags $commonTags "context=devops-self-hosted-agent"

# Create Web App Azure self-hosted agent
$appId = $(az webapp create --name $appName --resource-group $resourceGroupName `
                            --plan $appServicePlanName --deployment-container-image-name "$($acrName).azurecr.io/azagent:latest" `
                            --tags $commonTags "context=devops-self-hosted-agent" --output tsv --query "id")
$appPrincipalId = $(az webapp identity assign --name $appName --resource-group $resourceGroupName --output tsv --query principalId)

az webapp update --name $appName --resource-group $resourceGroupName --https-only
az webapp config set --name $appName --resource-group $resourceGroupName --always-on $true --ftps-state Disabled --vnet-route-all-enabled $true

# Add roles
$keyVaultId = $(az keyvault show --resource-group $resourceGroupName --name $keyVaultName --query "id" --output tsv)
$acrId = $(az acr show --resource-group $resourceGroupName --name $acrName --query "id" --output tsv)

az role assignment create --assignee-object-id $appPrincipalId --assignee-principal-type ServicePrincipal --scope $keyVaultId --role "Key Vault Secrets User"
az role assignment create --assignee-object-id $appPrincipalId --assignee-principal-type ServicePrincipal --scope $acrId --role "AcrPull"

# Setup vnet integration
az webapp vnet-integration add --name $appName --resource-group $resourceGroupName --vnet $vnetName --subnet "SelfHostedSubNet"

# Add settings
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings AZP_POOL=$AZP_POOL
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings AZP_AGENT_NAME=$AZP_AGENT_NAME
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings AZP_URL=$AZP_URL
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings "AZP_TOKEN=""@Microsoft.KeyVault(VaultName=$($keyVaultName);SecretName=azp-token)"""
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings WEBSITES_CONTAINER_START_TIME_LIMIT=1800
az webapp config appsettings set --name $appName --resource-group $resourceGroupName --settings WEBSITES_PORT=8000

# Configure the app to use the managed identity to pull from Azure Container Registry
az webapp config set --name $appName --resource-group $resourceGroupName --generic-configurations '{\"acrUseManagedIdentityCreds\": true}'

# Setup private endpoint
$webAppEndpointName = "pesites$($appName.Replace('-', ''))"
az network private-endpoint create `
    --name $webAppEndpointName `
    --resource-group $resourceGroupName `
    --vnet-name $vnetName --subnet "PrivateEndpointSubNet" `
    --private-connection-resource-id $appId `
    --group-id sites `
    --connection-name "plssites$($appName.Replace('-', ''))" `
    --tags $commonTags

# Configure private DNS
$dnsZone = "privatelink.azurewebsites.net"
az network private-dns zone create --resource-group $resourceGroupName --name $dnsZone --tags $commonTags

# Link the Private DNS Zone to the Virtual Network
az network private-dns link vnet create --zone-name $dnsZone --resource-group $resourceGroupName `
                                        --name "PrivateLink" --registration-enabled false --virtual-network $vnetName

# Create private endpoint dns entry
az network private-endpoint dns-zone-group create `
    --resource-group $resourceGroupName `
    --endpoint-name $webAppEndpointName `
    --name "default" `
    --private-dns-zone $dnsZone `
    --zone-name $dnsZone.Replace('.', '-')