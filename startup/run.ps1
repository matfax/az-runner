using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Information "[INFO] Running startup script..."

# Ensure that the header contains 'workflow_job' event
$eventType = $Request.Headers["X-GitHub-Event"]
if ($eventType -ne "workflow_job") {
    Write-Information "[SKIPPING] Irrelevant event type '$eventType'"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Irrelevant event type '$eventType', expected 'workflow_job'"
    })
    return
}

# Ensure that header contains HMAC
if ($null -eq $Request.Headers["X-Hub-Signature-256"]) {
    Write-Warning "[WARNING] Missing HMAC signature in header"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "Missing HMAC signature in header"
    })
    return
}

# Ensure that env:GITHUB_WEBHOOK_SECRET is defined
if ($null -eq $env:GITHUB_WEBHOOK_SECRET) {
    Write-Error "[ERROR] Missing environment variable 'GITHUB_WEBHOOK_SECRET'"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Missing environment variables on system"
    })
    return
}

# Calculate HMAC signature
try {
    Write-Information "[INFO] Calculating HMAC of payload..."
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.Key = [Text.Encoding]::UTF8.GetBytes($env:GITHUB_WEBHOOK_SECRET)
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($Request.rawbody)
    $computedHash = $hmacsha.ComputeHash($payloadBytes)
    $computedSignature = "sha256=" + [Convert]::ToHexString($computedHash).ToLower().Replace("-", "")
    Write-Verbose "Computed hash: $computedSignature"

    $receivedSignature = $Request.Headers['X-Hub-Signature-256']
    Write-Verbose "Received hash: $receivedSignature"
}
catch {
    Write-Error "[ERROR] Error calculating HMAC signature: $_"
    Write-Verbose "Raw Payload:"
    Write-Verbose $Request.rawbody
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Failed to calculate HMAC for payload"
    })
    return
}

# Verify HMAC signature
if ($computedSignature -ne $receivedSignature) {
    Write-Error "[ERROR] Invalid HMAC signature for payload with size $($Request.rawbody.Length) bytes:"
    Write-Verbose $Request.rawbody
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Unauthorized
        Body = "Invalid HMAC signature for payload"
    })
    return
}

# Ensure that the webhook type is 'workflow_job'
if ($null -eq $Request.Body.workflow_job) {
    Write-Error "[ERROR] Unable to find 'workflow_job' element in payload"
    Write-Verbose "Raw Payload:"
    Write-Verbose $Request.rawbody
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Invalid webhook payload"
    })
    return
}

$workflowJob = $Request.Body.workflow_job

# Check if the workflow job is queued
if ($Request.Body.action -ne "queued") {
    Write-Information "[SKIPPING] Trigger action of workflow job is not 'queued'"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Ignoring trigger of non-queued workflow job"
    })
    return
}

# Check that the workflow job uses the correct labels
$labels = $workflowJob.labels

if ($labels -notcontains "azure" || $labels -notcontains "production") {
    Write-Information "[SKIPPING] Ignoring job without the 'azure' and 'production' runner labels"
    Write-Verbose "Actual Labels:"
    foreach ($label in $labels) {
        Write-Verbose "- $label"
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Continue
        Body = "Ignoring job without the 'azure' and 'production' runner labels"
    })
    return
}

# Check if the request contains repository data
$repo = $Request.Body.repository
if (-not $repo) {
    Write-Error "[ERROR] Repository data is missing from the webhook payload"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Repository data is missing from the webhook payload"
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
    Write-Error "[ERROR] One or more required environment variables or secrets are inaccessible or missing"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Internal System Error"
    })
    return
}

# Construct the path to create.ps1
$createScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "../create.ps1"

# Call create.ps1 with the required parameters
try {
    Write-Information "[INFO] Calling create.ps1..."

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
    Write-Error "[ERROR] Error creating container group: $_"
    $responseBody = "Failed to create container group: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
}

# Return the response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $responseBody
})

Write-Information "[INFO] Startup successful"
