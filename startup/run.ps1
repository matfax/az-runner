using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Ensure that header contains HMAC
if ($null -eq $Request.Headers["X-Hub-Signature-256"]) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "Missing HMAC signature in header."
    })
    return
}

# Ensure that env:GITHUB_WEBHOOK_SECRET is defined
if ($null -eq $env:GITHUB_WEBHOOK_SECRET) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Missing environment variables on system."
    })
    return
}

# Calculate HMAC signature
try {
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.Key = [Text.Encoding]::UTF8.GetBytes($env:GITHUB_WEBHOOK_SECRET)
    $compressedJson = $Request.Body | ConvertTo-Json -Compress -ErrorAction Stop
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($compressedJson)
    $computedHash = $hmacsha.ComputeHash($payloadBytes)
    $computedSignature = "sha256=" + [Convert]::ToHexString($computedHash).ToLower()
    $receivedSignature = $Request.Headers['X-Hub-Signature-256']
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Failed to process JSON for HMAC from payload: $compressedJson"
    })
    return
}

# Verify HMAC signature
if ($computedSignature -ne $receivedSignature) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "Invalid authorization signature for payload: $compressedJson"
    })
    return
}

$Payload = $Request.Body

# Ensure that the header contains 'workflow_job' event
if ($Request.Headers["X-GitHub-Event"] -ne "workflow_job") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Invalid header 'X-GitHub-Event'. Expected 'workflow_job'."
    })
    return
}

# Ensure that the webhook type is 'workflow_job'
if ($null -eq $Payload.workflow_job) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Invalid webhook event type. Expected 'workflow_job'."
    })
    return
}

# Assign the workflow_job object to a new variable
$workflowJob = $Payload.workflow_job

# Now you can use $workflowJob to access the workflow job data

# Check if the workflow job is queued
if ($Payload.action -ne "queued") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Ignoring non-queued workflow job trigger."
    })
    return
}

# Check that the workflow job uses the correct labels
$ labels = $workflowJob.labels

if ($labels -notcontains "azure" || $labels -notcontains "production") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Ignoring job without the 'azure' and 'production' runner labels."
    })
    return
}

# Check if the request contains repository data
$repo = $Payload.repository
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

# Check the token expiration date
$tokenExpiration = [datetime]::Parse($Request.Headers["X-MS-TOKEN-GITHUB-EXPIRES-ON"])
$currentTime = [datetime]::UtcNow

if ($tokenExpiration -lt $currentTime) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "GitHub App access token has expired."
    })
    return
}

# Get environment variables and secrets
$acrPassword = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-acr-token
#$githubToken = Get-AzKeyVaultSecret -VaultName $env:AZ_KV_NAME -Name az-runner-github-registration-access -AsPlainText
$githubToken = $Request.Headers["X-MS-TOKEN-GITHUB-ACCESS-TOKEN"]

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
