param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$keyVaultName,
    [string]$logAnalyticsWorkspaceName,
    [string]$vnetName,
    [string]$currentUserId,
    [string]$AZP_TOKEN,
    [string]$commonTags
)

# Add key vault
$keyVaultId = $(az keyvault create --name $keyVaultName --resource-group $resourceGroupName --location $location `
                                   --sku Standard --enable-soft-delete $true --enable-purge-protection $true `
                                   --enable-rbac-authorization $true `
                                   --tags $commonTags `
                                   --output tsv --query "id")

az role assignment create --role "Key Vault Secrets Officer" --assignee $currentUserId --scope $keyVaultId

# Create secret for the Azure DevOps token
az keyvault secret set --vault-name $keyVaultName --name "azp-token" --value $AZP_TOKEN

# Enable diagnostic settings
az monitor diagnostic-settings create --workspace $logAnalyticsWorkspaceName --resource $keyVaultId --name "Key vault logs" `
                                      --logs '[{"category": "AuditEvent","enabled": true}]' --metrics '[{"category": "AllMetrics","enabled": true}]'

# Setup private endpoint
$keyvaultEndpointName = "pevault$($keyVaultName.Replace('-', ''))"
az network private-endpoint create `
                --name $keyvaultEndpointName `
                --resource-group $resourceGroupName `
                --vnet-name $vnetName --subnet "PrivateEndpointSubNet" `
                --private-connection-resource-id $keyvaultId `
                --group-id vault `
                --connection-name "plsvault$($keyVaultName.Replace('-', ''))" `
                --tags $commonTags

# Configure private DNS
$dnsZone = "privatelink.vaultcore.azure.net"
az network private-dns zone create --resource-group $resourceGroupName --name $dnsZone --tags $commonTags

# Link the Private DNS Zone to the Virtual Network
az network private-dns link vnet create --zone-name $dnsZone --resource-group $resourceGroupName `
                                        --name "PrivateLink" --registration-enabled false --virtual-network $vnetName

# Create private endpoint dns entry
az network private-endpoint dns-zone-group create `
                --resource-group $resourceGroupName `
                --endpoint-name $keyvaultEndpointName `
                --name 'default' `
                --private-dns-zone $dnsZone `
                --zone-name $dnsZone.Replace('.', '-')

# Remove public access to Key Vault
az keyvault update --name $keyVaultName --resource-group $resourceGroupName --default-action deny --bypass None