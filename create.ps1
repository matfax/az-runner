param (
    [string]$ContainerGroupName,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$ACRName,
    [string]$ACRUsername,
    [securestring]$ACRPassword,
    [string]$GithubServerUrl,
    [string]$GithubRepository,
    [securestring]$RunnerToken,
    [Hashtable]$ExtraArgs
)

# Process unexpected arguments
foreach ($key in $ExtraArgs.Keys) {
    Write-Host "Ignoring extra argument: $key with value $($ExtraArgs[$key])"
}

# Define environment variables
$repoEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "REPO_URL" -Value "$GithubServerUrl/$GithubRepository"
$runnerNameEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_NAME" -Value $ContainerGroupName
$runnerScopeEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_SCOPE" -Value "repo"
$labelsEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "LABELS" -Value "linux,x64,azure"
$ephemeralEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "EPHEMERAL" -Value "1"

# Define secure environment variable
$runnerTokenEnv = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_TOKEN" -SecureValue $RunnerToken

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
