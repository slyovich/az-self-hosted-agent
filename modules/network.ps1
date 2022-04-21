param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$vnetName,
    [string]$vnetAddresses,
    [string]$privateEndpointSubnetAddresses,
    [string]$appSrvSubnetAddresses,
    [string]$nsgName,
    [string]$commonTags
)

# Add Network Security Group
az network nsg create --name $nsgName --resource-group $resourceGroupName --location $location --tags $commonTags

# Add Hub Virtual Network
az network vnet create --name $vnetName --address-prefixes $vnetAddresses `
                       --resource-group $resourceGroupName --location $location `
                       --tags $commonTags "context=hub-network"

# Add private endpoints subnet
az network vnet subnet create --name "PrivateEndpointSubNet" --vnet-name $vnetName --resource-group $resourceGroupName `
                              --address-prefixes $privateEndpointSubnetAddresses --network-security-group $nsgName `
                              --disable-private-endpoint-network-policies $true --disable-private-link-service-network-policies $false

# Add vnet integration subnet
az network vnet subnet create --name "AppSrvSubNet" --vnet-name $vnetName --resource-group $resourceGroupName `
                              --address-prefixes $appSrvSubnetAddresses --network-security-group $nsgName --delegations "Microsoft.Web/serverFarms" `
                              --disable-private-endpoint-network-policies $false --disable-private-link-service-network-policies $false