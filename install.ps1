param(
    [Parameter(Mandatory=$true)]
    [string]$ModuleName
)

# Check if the Modules directory exists, create it if not
$moduleDir = "./Modules"
if (!(Test-Path $moduleDir)) {
    New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null
    Write-Host "Created directory: $moduleDir"
}

# Split PSModulePath into an array of paths
$modulePaths = $env:PSModulePath -split ';'

# Add common module path to condidates
$modulePaths += "C:\Program Files\PowerShell\Modules"

# Find the first path where the Module exists
foreach ($path in $modulePaths) {
    $fullPath = Join-Path -Path $path -ChildPath $ModuleName
    if (Test-Path $fullPath) {
        $foundModulePath = $fullPath
        break
    }
}

# Throw an exception if the Module was not found
if (-not $foundModulePath) {
    throw "Module '$ModuleName' not found in any of the paths in PSModulePath"
}

# Copy the Module to the current directory's ./Module/ path
$destPath = Join-Path -Path $moduleDir -ChildPath $ModuleName
Copy-Item -Path $foundModulePath -Destination $destPath -Recurse -Force
Write-Host "Copied Module '$ModuleName' to: $destPath"
