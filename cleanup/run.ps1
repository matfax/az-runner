# Input bindings are passed in via param block.
param($Timer)

Write-Information "[INFO] Cleaning up superfluous runners..."

$ResourceGroupName = $env:AZ_RES_GROUP

if ($null -eq $ResourceGroupName) {
    Write-Error "[ERROR] Environment variable 'AZ_RES_GROUP' not set" -ErrorAction Stop
}

$currentTime = [datetime]::UtcNow
$42MinAgo = $currentTime.AddMinutes(-42)

# Check if container group already exists
$containerGroups = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

foreach($group in $containerGroups) {
    $name = $group.Container.Name
    $startTime = $group.Container.CurrentStateStartTime

    Write-Verbose "[INFO] Start time of $name\: $startTime"

    if ($startTime -le $42MinAgo) {
        $diffTime = $currentTime - $startTime
        $diffMins = $diffTime.Minute
        Write-Information "[INFO] Cleaning up $name ($diffMins unused)..."
        $group | Remove-AzContainerGroup
    }
}

Write-Information "[INFO] Cleanup complete!"
