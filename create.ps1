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
    [string[]]$Labels,
    [Parameter(Mandatory=$false)]
    [int]$RequestCpu=1,
    [Parameter(Mandatory=$false)]
    [int]$RequestMemory=2,
    [Parameter(Mandatory=$false)]
    [switch]$NoWait,
    [Parameter(Mandatory=$false)]
    [switch]$AppendSpecs,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

# Set cores and memory if labels contain metadata
$Labels | ForEach-Object {
    if ($_ -match '^(\d+)-(cores|gb)$') {
        $value = [int]$Matches[1]
        switch ($Matches[2]) {
            'cores' { $RequestCpu = [Math]::Min($value, 8) }
            'gb'    { $RequestMemory = [Math]::Min($value, 32) }
        }
    }
}

# Append hardware specs to container name
if ($AppendSpecs) {
    $ContainerGroupName += "-$($RequestCpu)core$($RequestMemory)gb"
}

# Check if container group already exists
$containerGroup = Get-AzContainerGroup -Name $ContainerGroupName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

Write-Information "Container group '$ContainerGroupName' exists: $($null -ne $containerGroup)"
if ($containerGroup) {
    Write-Host "Container group already exists."
    return $containerGroup
} else {
    Write-Host "Container group does not exist; creating..."
}

# GitHub API URL
$apiUrl = "https://api.github.com/repos/$GithubRepository/actions/runners/registration-token"

# Headers for the API request
$headers = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $GithubToken"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# Make the API request
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers
    $regToken = $response.token

    # Convert the registration token to a SecureString
    $secureRegToken = ConvertTo-SecureString $regToken -AsPlainText -Force

    if (-not $secureRegToken) {
        Write-Error "Failed to convert token to secure string." -ErrorAction Stop
    }

    Write-Host "Registration token obtained and stored as a secure string."
}
catch {
    Write-Error "Failed to obtain registration token" -ErrorAction Stop
}

# Define environment variables
$repoEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "REPO_URL" -Value "https://github.com/$GithubRepository"
$runnerNameEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_NAME" -Value $ContainerGroupName
$runnerScopeEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_SCOPE" -Value "repo"
$labelsEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "LABELS" -Value ($Labels -join ',')
$ephemeralEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "EPHEMERAL" -Value "1"

# Define secure environment variable
$runnerTokenEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_TOKEN" -SecureValue $secureRegToken

# Define container instance
$container = New-AzContainerInstanceObject `
    -Name $ContainerGroupName `
    -Image "$ACRName.azurecr.io/az-runner" `
    -RequestCpu $RequestCpu `
    -RequestMemoryInGb $RequestMemory `
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
    -ImageRegistryCredential $imageRegistryCredential `
    -NoWait:$NoWait
    
Write-Host "Container group '$ContainerGroupName' created successfully." -ForeGroundColor Green
return $true
