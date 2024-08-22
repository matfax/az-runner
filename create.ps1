param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$Location,
    [Parameter(Mandatory=$true)]
    [string]$ACRName,
    [Parameter(Mandatory=$true)]
    [string]$ACRUsername,
    [Parameter(Mandatory=$true)]
    [securestring]$ACRPassword,
    [Parameter(Mandatory=$true)]
    [string]$GithubServerUrl,
    [Parameter(Mandatory=$true)]
    [string]$GithubRepository,
    [Parameter(Mandatory=$true)]
    [string]$GithubToken,
    [Hashtable]$ExtraArgs
)

# Process unexpected arguments
if ($ExtraArgs -ne $null) {
    Write-Host "Ignoring extra arguments: $($ExtraArgs.Keys)"
}

# GitHub API URL
$apiUrl = "https://api.github.com/repos/$Repository/actions/runners/registration-token"

# Headers for the API request
$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $GithubToken"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$secureRegToken = $null

# Make the API request
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers
    $regToken = $response.token

    # Convert the registration token to a SecureString
    $secureRegToken = ConvertTo-SecureString $regToken -AsPlainText -Force

    if ($null -eq $secureRegToken) {
        throw "Failed to convert token to secure string."
    }

    Write-Output "Registration token obtained and stored as a secure string."
}
catch {
    Write-Error "Failed to obtain registration token."
    exit 1
}

# Define environment variables
$repoEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "REPO_URL" -Value "$GithubServerUrl/$GithubRepository"
$runnerNameEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_NAME" -Value $ContainerGroupName
$runnerScopeEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_SCOPE" -Value "repo"
$labelsEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "LABELS" -Value "linux,x64,azure"
$ephemeralEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "EPHEMERAL" -Value "1"

# Define secure environment variable
$runnerTokenEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_TOKEN" -SecureValue $secureRegToken

# Define container instance
$container = New-AzContainerInstanceObject `
    -Name $ContainerGroupName `
    -Image "$ACRName.azurecr.io/az-runner" `
    -RequestCpu 1 `
    -RequestMemoryInGb 2 `
    -EnvironmentVariable @($repoEnv, $runnerNameEnv, $runnerScopeEnv, $labelsEnv, $ephemeralEnv) `
    -SecureEnvironmentVariable @($runnerTokenEnv)

# Define image registry credentials
$imageRegistryCredential = New-AzContainerGroupImageRegistryCredentialObject `
    -Server "$ACRName.azurecr.io" `
    -Username $ACRUsername `
    -Password $ACRPassword

# Create the container group
New-AzContainerGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name $ContainerGroupName `
    -Location $Location `
    -Container $container `
    -OsType Linux `
    -RestartPolicy Never `
    -ImageRegistryCredential $imageRegistryCredential
