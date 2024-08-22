param (
    [string]$ContainerGroupName,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$ACRName,
    [string]$ACRUsername,
    [string]$ACRPassword,
    [string]$GithubServerUrl,
    [string]$GithubRepository,
    [string]$RunnerToken
)

# Define environment variables
$env1 = New-AzContainerInstanceEnvironmentVariableObject -Name "REPO_URL" -Value "$GithubServerUrl/$GithubRepository"
$env2 = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_NAME" -Value $ContainerGroupName
$env3 = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_SCOPE" -Value "repo"
$env4 = New-AzContainerInstanceEnvironmentVariableObject -Name "LABELS" -Value "linux,x64,azure"
$env5 = New-AzContainerInstanceEnvironmentVariableObject -Name "EPHEMERAL" -Value "1"

# Define secure environment variable
$envSecure1 = New-AzContainerInstanceEnvironmentVariableObject -Name "RUNNER_TOKEN" -SecureValue (ConvertTo-SecureString -String $RunnerToken -AsPlainText -Force)

# Define container instance
$container = New-AzContainerInstanceObject `
    -Name $ContainerGroupName `
    -Image "$ACRName.azurecr.io/az-runner" `
    -RequestCpu 1 `
    -RequestMemoryInGb 2 `
    -EnvironmentVariable @($env1, $env2, $env3, $env4, $env5) `
    -SecureEnvironmentVariable @($envSecure1)

# Define image registry credentials
$imageRegistryCredential = New-AzContainerGroupImageRegistryCredentialObject `
    -Server "$ACRName.azurecr.io" `
    -Username $ACRUsername `
    -Password (ConvertTo-SecureString -String $ACRPassword -AsPlainText -Force)

# Create the container group
New-AzContainerGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name $ContainerGroupName `
    -Location $Location `
    -Container $container `
    -OsType Linux `
    -RestartPolicy Never `
    -ImageRegistryCredential $imageRegistryCredential
