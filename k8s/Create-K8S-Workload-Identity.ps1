function CreateK8SWorkloadIdentity {
    $ResourceGroup = "k8s-to-blobstorage"
    $Location = "polandcentral"
    $ClusterName = "awi-k8s-cluster"
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
        --node-vm-size "Standard_B2ats_v2" `
        --node-count 1 `
        ---tier free `

    $AksOidcIssuer = $(
        az aks show --name $ClusterName --resource-group $ResourceGroup --query "oidcIssuerProfile.issuerUrl" --output tsv
    )
    $UserAssignedClientId = $(
        az identity show --name $UserAssignedIdentityName --resource-group $ResourceGroup --query "clientId" --output tsv
    )
    az aks get credentials --name $ClusterName --resource-group $ResourceGroup
    
    $ServiceAccountTemplate = Get-Content -Path "serviceAccounts/cat-api.serviceAccount.yml" -Raw `
        -replace "{{USER_ASSIGNED_CLIENT_ID}}", $UserAssignedClientId `
        -replace "{{SERVICE_ACCOUNT_NAME}}", $ServiceAccountName `
        -replace "{{SERVICE_ACCOUNT_NAMESPACE}}", $ServiceAccountNamespace
    $ServiceAccountTemplate | kubectl apply -f -
    
    az identity federated-credential create `
        --name $FederatedIdentityCredentialName `
        --identity-name $UserAssignedIdentityName `
        --resource-group $ResourceGroup `
        --issuer $AksOidcIssuer `
        --subject "system:serviceaccount:${ServiceAccountNamespace}:${ServiceAccountName}" `
        --audience "api://AzureADTokenExchange"

    
}