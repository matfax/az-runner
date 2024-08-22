param (
    [string]$ContainerGroupName,
    [string]$ResourceGroupName,
    [Hashtable]$ExtraArgs
)

# Process unexpected arguments
Write-Host "Ignoring extra arguments: $ExtraArgs.Keys"

Remove-AzContainerGroup `
    -Name $ContainerGroupName `
    -ResourceGroupName $ResourceGroupName `
    -Confirm
