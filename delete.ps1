param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Hashtable]$ExtraArgs
)

# Process unexpected arguments
if ($ExtraArgs -ne $null) {
    Write-Host "Ignoring extra arguments: $($ExtraArgs.Keys)"
}

Remove-AzContainerGroup `
    -Name $ContainerGroupName `
    -ResourceGroupName $ResourceGroupName `
    -Confirm
