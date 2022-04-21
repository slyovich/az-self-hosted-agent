param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$storageAccountName,
    [string]$commonTags
)

# Create terraform storage account
az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location `
                          --access-tier hot --kind "StorageV2" --sku "Standard_LRS" --https-only `
                          --allow-blob-public-access false --allow-cross-tenant-replication false `
                          --allow-shared-key-access true  --min-tls-version "TLS1_2" `
                          --tags $commonTags "context=terraform-state"

# Add container for terraform state file
az storage container create --name "tfstate" --account-name $storageAccountName --resource-group $resourceGroupName --auth-mode key