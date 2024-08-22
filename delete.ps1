param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

Remove-AzContainerGroup `
    -Name $ContainerGroupName `
    -ResourceGroupName $ResourceGroupName `
    -Confirm
