# Input bindings are passed in via param block.
param($Timer)

Write-Host "Cleaning up superfluous runners..."

$ResourceGroupName = $env:AZ_RES_GROUP

if ($null -eq $ResourceGroupName) {
    Write-Error "Environment variable 'AZ_RES_GROUP' not set" -ErrorAction Stop
}

$currentTime = [datetime]::UtcNow
$42MinAgo = $currentTime.AddMinutes(-42)

# Check if container group already exists
$containerGroups = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $containerGroups) {
    Write-Information "No container groups found."
    return
}

$insightsToken = Get-AzAccessToken -ResourceUrl "https://api.loganalytics.io" -AsSecureString -ErrorAction Stop -WarningAction SilentlyContinue

if (-not $insightsToken) {
    Write-Error "Access token for Log Analytics could not be obtained" -ErrorAction Stop
}

Write-Host "Obtained access token for Log Analytics"

$subscriptionId = $env:AZ_SUBSCRIPTION_ID

if (-not $subscriptionId) {
    Write-Error "Environment variable 'AZ_SUBSCRIPTION_ID' not set" -ErrorAction Stop
}

# App Insights API Data
$apiUrl = "https://api.applicationinsights.io/v1/subscriptions/$subscriptionId/resourceGroups/github/providers/microsoft.insights/components/az-runner/query?timespan=P0Y0M0DT0H42M"

$requestBody = @"
{
  "query": "valid_startup_requests_extended | summarize count() by container_name"
}
"@

# Headers for the API request
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $($insightsToken.Token | ConvertFrom-SecureString -AsPlainText)"
}

$ignoreList = [ordered]@{}

# Make the API request
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $requestBody -ErrorAction Stop

    if (-not $response.tables || -not $response.tables[0]) {
        Write-Debug $response.tables | Format-List
        Write-Error "No data returned from API" -ErrorAction Stop
    }

    $table = $response.tables[0]
    foreach ($row in $table.rows) {
        $container_name = $row[0]
        $count = [long]$row[1]
        $ignoreList[$container_name] = $count
        Write-Verbose "Container $container_name has $count recent startup requests"
    }
}
catch {
    Write-Error "Failed to obtain recent startup requests: $_" -ErrorAction Stop
}

foreach($group in $containerGroups) {
    $details = $group | Get-AzContainerGroup
    $name = $details.Container.Name
    $startTime = [datetime]$details.Container.CurrentStateStartTime

    Write-Verbose "Start time of $name\: $startTime"

    if ($startTime -le $42MinAgo) {
        if ($ignoreList.Contains($name)) {
            Write-Information "[SKIPPING] Container $name has $($ignoreList[$name]) recent startup requests, not cleaning up"
            continue
        }

        $diffTime = $currentTime - $startTime
        $diffMins = $diffTime.TotalMinutes
        Write-Information "Cleaning up $name ($diffMins minutes unused)..."
        $group | Remove-AzContainerGroup
    }
}

Write-Information "Cleanup complete!"
