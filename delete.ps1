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
    $containerGroup | Remove-AzContainerGroup -Confirm
} else {
    Write-Error "Container group not found."
    exit 1
}