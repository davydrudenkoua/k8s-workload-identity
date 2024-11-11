function CreateK8SWorkloadIdentity {
    $ResourceGroup = "k8s-to-blobstorage"
    $Location = "polandcentral"
    $ClusterName = "cats-api-k8s"
    $ServiceAccountNamespace = "default"
    $ServiceAccountName="cats-api-sa"
    $SubscriptionId = $(az account show --query "id" --output tsv)
    $UserAssignedIdentityName="CatsApiUserAssignedIdentity"
    $FederatedIdentityCredentialName="CatsApiFederatedIdentity"

    Write-Host "Creating identity $UserAssignedIdentityName..."
    az identity create `
        --name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --location $Location `
        --subscription $SubscriptionId
    Write-Host "Identity $UserAssignedIdentityName created"

    Write-Host "Creating AKS $ClusterName..."
    az aks create `
        --resource-group $ResourceGroup `
        --name $ClusterName `
        --enable-oidc-issuer `
        --enable-workload-identity `
        --generate-ssh-keys `
        --location $Location `
        --node-vm-size "Standard_B2s" `
        --node-count 1 `
        --tier "free" `
        --load-balancer-sku basic
    Write-Host "AKS $ClusterName created"

    $AksOidcIssuer = $(
        az aks show --name $ClusterName --resource-group $ResourceGroup --query "oidcIssuerProfile.issuerUrl" --output tsv
    )
    $UserAssignedClientId = $(
        az identity show --name $UserAssignedIdentityName --resource-group $ResourceGroup --query "clientId" --output tsv
    )
    az aks get-credentials --name $ClusterName --resource-group $ResourceGroup
    Write-Host "AKS credentials saved"

    kubectl create secret docker-registry cats-api-registry-secret `
    --docker-server=https://index.docker.io/v1/ `
    --docker-username=$Env:DOCKER_USERNAME `
    --docker-password=$Env:DOCKER_PASSWORD
    Write-Host "AKS secret for pulling image created"

    Write-Host "Creating service account deployment..."
    $ServiceAccountTemplate = Get-Content -Path "k8s/serviceAccounts/cats-api.serviceAccount.yaml" -Raw
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{USER_ASSIGNED_CLIENT_ID}}", $UserAssignedClientId
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{SERVICE_ACCOUNT_NAME}}", $ServiceAccountName
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{SERVICE_ACCOUNT_NAMESPACE}}", $ServiceAccountNamespace
    Write-Host "Service account template to be applied:`n$ServiceAccountTemplate"
    $ServiceAccountTemplate | kubectl apply -f -

    Write-Host "Creating federated credential $FederatedIdentityCredentialName..."
    az identity federated-credential create `
        --name $FederatedIdentityCredentialName `
        --identity-name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --issuer $AksOidcIssuer `
        --subject "system:serviceaccount:${ServiceAccountNamespace}:${ServiceAccountName}" `
        --audience "api://AzureADTokenExchange"
    Write-Host "Federated credential $FederatedIdentityCredentialName created"

    Write-Host "Applying API deployment..."
    $DeploymentTemplate = Get-Content -Path "k8s/deployments/cats-api.deployment.yaml" -Raw
    $DeploymentTemplate = $DeploymentTemplate -replace "{{SERVICE_ACCOUNT_NAME}}", $ServiceAccountName
    Write-Host "API deployment to be applied:`n$DeploymentTemplate"
    $DeploymentTemplate | kubectl apply -f -

    $StorageAccountId = $(
        az storage account show `
        --resource-group $ResourceGroup `
        --name "davydscats" `
        --query "id" `
        --output tsv
    )
    $IdentityPrincipalId = $(
        az identity show `
        --name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --query "principalId" `
        --output tsv
    )

    Write-Host "Creating `"Storage Blob Data Contributor`" role assignment for storage account..."
    az role assignment create `
        --assignee-object-id $IdentityPrincipalId `
        --role "Storage Blob Data Contributor" `
        --scope $StorageAccountId `
        --assignee-principal-type "ServicePrincipal"
}

CreateK8SWorkloadIdentity