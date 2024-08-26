# Input bindings are passed in via param block.
param($Timer)

Write-Information "[INFO] Refreshing GitHub user access token"

$apiUrl = "https://az-runner.fax.fyi/.auth/refresh"

try {
    Invoke-RestMethod -Uri $apiUrl -Method Get
}
catch {
    Write-Error "[ERROR] Failed to refresh user access token: $_"
    exist 1
}

Write-Information "[INFO] Successfully refreshed GitHub user access token"
