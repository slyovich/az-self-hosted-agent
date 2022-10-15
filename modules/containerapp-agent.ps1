param(
    [string]$resourceGroupName,
    [string]$location,
    [string]$keyVaultName,
    [string]$acrName,
    [string]$selfHostedSubNetId,
    [string]$containerAppEnvironmentName,
    [string]$containerAppName,
    [string]$logAnalyticsWorkspaceCustomerId,
    [string]$logAnalyticsWorkspaceKey,
    [string]$AZP_POOL,
    [string]$AZP_AGENT_NAME,
    [string]$AZP_URL,
    [string]$AZP_TOKEN,
    [string]$commonTags
)

az containerapp env create `
  --name $containerAppEnvironmentName `
  --resource-group $resourceGroupName `
  --location $location `
  --infrastructure-subnet-resource-id $selfHostedSubNetId `
  --internal-only `
  --zone-redundant `
  --logs-workspace-id $logAnalyticsWorkspaceCustomerId `
  --logs-workspace-key $logAnalyticsWorkspaceKey `
  --tags $commonTags "context=devops-self-hosted-agent"

# https://github.com/Azure/terraform-provider-azapi/issues/152
$provisioningState = $(az containerapp env show --name $containerAppEnvironmentName --resource-group $resourceGroupName --query "properties.provisioningState" --output tsv)
while ($provisioningState -ne "Succeeded") {
    if ($provisioningState -eq "Failed") {
        throw 'Container App Environment provisioning failed'
    }

    Write-Host "Provisioning state $($provisioningState). Waiting 15 sec..."
    Start-Sleep -s 15
    $provisioningState = $(az containerapp env show --name $containerAppEnvironmentName --resource-group $resourceGroupName --query "properties.provisioningState" --output tsv)
}

az containerapp create `
  --name $containerAppName `
  --resource-group $resourceGroupName `
  --environment $containerAppEnvironmentName `
  --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest `
  --cpu 0.75 `
  --memory 1.5Gi `
  --min-replicas 1 `
  --max-replicas 3 `
  --secrets "azp-token-secret=$($AZP_TOKEN)" `
  --env-vars AZP_POOL=$AZP_POOL AZP_AGENT_NAME=$AZP_AGENT_NAME AZP_URL=$AZP_URL AZP_TOKEN=secretref:azp-token-secret  `
  --tags $commonTags "context=devops-self-hosted-agent"

$appPrincipalId = $(az containerapp identity assign --name $containerAppName --resource-group $resourceGroupName --system-assigned --output tsv --query principalId)

# Add roles
$acrId = $(az acr show --resource-group $resourceGroupName --name $acrName --query "id" --output tsv)
az role assignment create --assignee-object-id $appPrincipalId --assignee-principal-type ServicePrincipal --scope $acrId --role "AcrPull"

# Update container app with the image from our private container registry
az containerapp registry set `
  --name $containerAppName `
  --resource-group $resourceGroupName `
  --identity system `
  --server "$($acrName).azurecr.io"

az containerapp update `
  --name $containerAppName `
  --resource-group $resourceGroupName `
  --image "$($acrName).azurecr.io/azagent:latest"