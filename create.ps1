param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZ_RES_GROUP,
    [Parameter(Mandatory=$false)]
    [string]$Location = $env:AZ_LOCATION,
    [Parameter(Mandatory=$false)]
    [string]$ACRName = $env:ACR_NAME,
    [Parameter(Mandatory=$false)]
    [string]$ACRUsername = $env:ACR_USERNAME,
    [Parameter(Mandatory=$false)]
    [securestring]$ACRPassword = (ConvertTo-SecureString -String $env:ACR_PASSWORD -AsPlainText -Force),
    [Parameter(Mandatory=$false)]
    [string]$GithubRepository = $env:GITHUB_REPOSITORY,
    [Parameter(Mandatory=$false)]
    [string]$GithubToken = $env:GITHUB_PAT,
    [Parameter(Mandatory=$true)]
    [string]$Labels,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

# Check if container group already exists
$containerGroup = Get-AzContainerGroup -Name $ContainerGroupName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

if ($containerGroup) {
    Write-Output "Container group '$ContainerGroupName' already exists."
    return $containerGroup
} else {
    Write-Output "Container group '$ContainerGroupName' does not exist. Creating..."
}

# GitHub API URL
$apiUrl = "https://api.github.com/repos/$GithubRepository/actions/runners/registration-token"

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
    throw "Failed to obtain registration token."
}

# Define environment variables
$repoEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "REPO_URL" -Value "https://github.com/$GithubRepository"
$runnerNameEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_NAME" -Value $ContainerGroupName
$runnerScopeEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_SCOPE" -Value "repo"
$labelsEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "LABELS" -Value $Labels
$ephemeralEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "EPHEMERAL" -Value "1"

# Define secure environment variable
$runnerTokenEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_TOKEN" -SecureValue $secureRegToken

# Define container instance
$container = New-AzContainerInstanceObject `
    -Name $ContainerGroupName `
    -Image "$ACRName.azurecr.io/az-runner" `
    -RequestCpu 1 `
    -RequestMemoryInGb 2 `
    -EnvironmentVariable @($runnerTokenEnv, $repoEnv, $runnerNameEnv, $runnerGroupEnv, $runnerScopeEnv, $labelsEnv, $ephemeralEnv)

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
    -RestartPolicy 'Always' `
    -ImageRegistryCredential $imageRegistryCredential

Write-Host "Container group '$ContainerGroupName' created successfully." -ForeGroundColor Green
