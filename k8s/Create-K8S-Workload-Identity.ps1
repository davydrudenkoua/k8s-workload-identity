function CreateK8SWorkloadIdentity {
    $ResourceGroup = "k8s-to-blobstorage"
    $Location = "polandcentral"
    $ClusterName = "cats-api-k8s"
    $ServiceAccountNamespace = "default"
    $ServiceAccountName="cats-api-sa"
    $SubscriptionId = $(az account show --query "id" --output tsv)
    $UserAssignedIdentityName="CatsApiUserAssignedIdentity"
    $FederatedIdentityCredentialName="CatsApiFederatedIdentity"

    az identity create `
        --name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --location $Location `
        --subscription $SubscriptionId

    az aks create `
        --resource-group $ResourceGroup `
        --name $ClusterName `
        --enable-oidc-issuer `
        --enable-workload-identity `
        --generate-ssh-keys `
        --location $Location `
        --node-vm-size "Standard_B2s" `
        --node-count 1 `
        --tier "free"

    $AksOidcIssuer = $(
        az aks show --name $ClusterName --resource-group $ResourceGroup --query "oidcIssuerProfile.issuerUrl" --output tsv
    )
    $UserAssignedClientId = $(
        az identity show --name $UserAssignedIdentityName --resource-group $ResourceGroup --query "clientId" --output tsv
    )
    az aks get-credentials --name $ClusterName --resource-group $ResourceGroup
    
    $ServiceAccountTemplate = Get-Content -Path "k8s/serviceAccounts/cats-api.serviceAccount.yaml" -Raw
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{USER_ASSIGNED_CLIENT_ID}}", $UserAssignedClientId
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{SERVICE_ACCOUNT_NAME}}", $ServiceAccountName
    $ServiceAccountTemplate = $ServiceAccountTemplate -replace "{{SERVICE_ACCOUNT_NAMESPACE}}", $ServiceAccountNamespace
    $ServiceAccountTemplate | kubectl apply -f -

    az identity federated-credential create `
        --name $FederatedIdentityCredentialName `
        --identity-name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --issuer $AksOidcIssuer `
        --subject "system:serviceaccount:${ServiceAccountNamespace}:${ServiceAccountName}" `
        --audience "api://AzureADTokenExchange"

    $DeploymentTemplate = Get-Content -Path "k8s/deployments/cats-api.deployment.yaml" -Raw
    $DeploymentTemplate = $DeploymentTemplate -replace "{{SERVICE_ACCOUNT_NAME}}", $ServiceAccountName
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
    az role assignment create `
        --assignee-object-id $IdentityPrincipalId `
        --role "Storage Blob Data Contributor" `
        --scope $StorageAccountId `
        --assignee-principal-type "ServicePrincipal"
}

CreateK8SWorkloadIdentity