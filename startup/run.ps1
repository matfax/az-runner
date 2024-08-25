using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Ensure that the header contains 'workflow_job' event
if ($Request.Headers["X-GitHub-Event"] -ne "workflow_job") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Invalid header 'X-GitHub-Event'. Expected 'workflow_job'."
    })
    return
}

# Ensure that the webhook type is 'workflow_job'
if ($null -eq $Request.Body.workflow_job) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Invalid webhook event type. Expected 'workflow_job'."
    })
    return
}

# Assign the workflow_job object to a new variable
$workflowJob = $Request.Body.workflow_job

# Now you can use $workflowJob to access the workflow job data

# Check if the workflow job is queued
if ($Request.Body.action -ne "queued") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = "Ignoring non-queued workflow job trigger."
    })
    return
}

# Check that the workflow job uses the correct labels
$ labels = $workflowJob.labels

if ($labels -notcontains "azure" || $labels -notcontains "production") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = "Ignoring job without the 'azure' and 'production' runner labels."
    })
    return
}

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
$acrPassword = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-acr-token
$githubToken = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-github-registration-access -AsPlainText

# Ensure all required variables are present
if (-not ($acrPassword -and $githubToken)) {
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
        -ACRPassword $acrPassword `
        -GithubRepository "$orgOrUser/$repoName" `
        -GithubToken $githubToken `
        -Labels "linux,x64,azure,production"

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
