using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Check if the request contains repository data
$repo = $Request.Body.repository
if (-not $repo) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Repository data is missing from the webhook payload."
    })
    return
}

# Extract organization/user and repository name
$orgOrUser = $repo.owner.login
$repoName = $repo.name

# Construct the container group name
$containerGroupName = "az-runner-$orgOrUser-$repoName"

# Get environment variables and secrets
$resourceGroupName = $env:AZ_RES_GROUP
$location = $env:AZ_LOCATION
$acrName = $env:ACR_NAME
$acrUsername = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-acr-username -AsPlainText
$acrPassword = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-acr-token
$githubToken = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-github-registration-access -AsPlainText

# Ensure all required variables are present
if (-not ($resourceGroupName -and $location -and $acrName -and $acrUsername -and $acrPassword -and $githubToken)) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "One or more required environment variables or secrets are missing."
    })
    return
}

# Construct the path to create.ps1
$createScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "../create.ps1"

# Call create.ps1 with the required parameters
try {
    & $createScriptPath `
        -ContainerGroupName $containerGroupName `
        -ResourceGroupName $resourceGroupName `
        -Location $location `
        -ACRName $acrName `
        -ACRUsername $acrUsername `
        -ACRPassword $acrPassword `
        -GithubRepository "$orgOrUser/$repoName" `
        -GithubToken $githubToken `
        -Labels "linux,x64,azure,production" `
        -RunnerGroupName "Azure"

    $responseBody = "Successfully created container group: $containerGroupName"
    $statusCode = [HttpStatusCode]::OK
}
catch {
    $responseBody = "Failed to create container group: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
}

# Return the response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $responseBody
})
