# tools\init.ps1
# FIX: four params are required — PMC passes them automatically
param($installPath, $toolsPath, $package, $project)

# FIX: use $toolsPath instead of $PSScriptRoot — PMC passes this in pointing to the tools\ folder
$scriptPath = Join-Path $toolsPath 'Add-StoredProcedure.ps1'
if (Test-Path $scriptPath) {
    . $scriptPath
    Write-Host 'Add-StoredProcedure command loaded. Use: Add-StoredProcedure -Help'
}