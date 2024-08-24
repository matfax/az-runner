param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerGroupName,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

$containerGroup = Get-AzContainerGroup -Name $ContainerGroupName -ResourceGroupName $ResourceGroupName

if ($containerGroup) {
    $containerGroup | Remove-AzContainerGroup
} else {
    throw "Container group not found."
}
