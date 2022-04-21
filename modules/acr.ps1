param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$logAnalyticsWorkspaceName,
    [string]$acrName,
    [string]$currentUserId,
    [string]$commonTags
)

# Create container registry
$acrId = $(az acr create --name $acrName --resource-group $resourceGroupName --location $location `
                         --sku Standard --admin-enabled $false --workspace $logAnalyticsWorkspaceName --tags $commonTags `
                         --output tsv --query "id")

# Grant current account push access
az role assignment create --assignee $currentUserId --scope $acrId --role "AcrPush"

# Compile az-agent and publish it to ACR
$acrToken=$(az acr login --name $acrName --expose-token --output tsv --query accessToken)
docker login "$($acrName).azurecr.io" --username 00000000-0000-0000-0000-000000000000 --password $acrToken
docker build az-agent -t azagent
docker tag azagent "$($acrName).azurecr.io/azagent:latest"
docker push "$($acrName).azurecr.io/azagent"