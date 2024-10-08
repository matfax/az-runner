param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZ_RES_GROUP,
    [Parameter(Mandatory=$false)]
    [string]$GithubRepository = $env:GITHUB_REPOSITORY,
    [Parameter(Mandatory=$false)]
    [string]$GithubToken = $env:GITHUB_PAT,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

# Check if container group already exists
Get-AzContainerGroup -Name $ContainerGroupName -ResourceGroupName $ResourceGroupName -ErrorAction Stop

Write-Host "Container group '$ContainerGroupName' exists." -ForegroundColor Green

# GitHub API URL
$apiUrl = "https://api.github.com/repos/$GithubRepository/actions/runners"

# Headers for the API request
$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $GithubToken"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# Fetching runner information from GitHub

$response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers

# If no runners found with expected name, exit the script
if ($response.total_count -eq 0) {
    throw "No runners found in the repository."
} elseif ($null -eq $response.runners | Where-Object { $_.name -eq $ContainerGroupName }) {
    throw "Runner '$ContainerGroupName' not found in the repository."
}

Write-Host "Runner '$ContainerGroupName' found." -ForegroundColor Green
