# Input bindings are passed in via param block.
param($Timer)

Write-Information "Cleaning up superfluous runners..."

$ResourceGroupName = $env:AZ_RES_GROUP

if ($null -eq $ResourceGroupName) {
    Write-Error "Environment variable 'AZ_RES_GROUP' not set." -ErrorAction Stop
}

$currentTime = [datetime]::Now()
$42MinAgo = $currentTime.AddMinutes(-42)

# Check if container group already exists
$containerGroups = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

foreach($group in $containerGroups) {
    $name = $group.Container.Name
    $startTime = $group.Container.CurrentStateStartTime

    Write-Verbose "Start time of $name\: $startTime"

    if ($startTime -le $42MinAgo) {
        Write-Information "Cleaning up $name..."
        $group | Remove-AzContainerGroup
    }
}
