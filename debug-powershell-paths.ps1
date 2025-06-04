#!/usr/bin/env pwsh
################################################################################
## Debug PowerShell Paths for Installation Scripts
################################################################################

Write-Host "=== PowerShell Environment Debug ===" -ForegroundColor Cyan

Write-Host "Environment Variables:" -ForegroundColor Yellow
Write-Host "  HELPER_SCRIPTS: $env:HELPER_SCRIPTS"
Write-Host "  INSTALLER_SCRIPT_FOLDER: $env:INSTALLER_SCRIPT_FOLDER"
Write-Host "  PWD: $PWD"
Write-Host "  HOME: $env:HOME"

Write-Host "`nPath Resolution Test:" -ForegroundColor Yellow
$helpersPath = "$env:HELPER_SCRIPTS/../tests/Helpers.psm1"
Write-Host "  Helpers.psm1 path: $helpersPath"
Write-Host "  Helpers.psm1 exists: $(Test-Path $helpersPath)"

$toolsetPath = "$env:INSTALLER_SCRIPT_FOLDER/toolset.json"
Write-Host "  toolset.json path: $toolsetPath"
Write-Host "  toolset.json exists: $(Test-Path $toolsetPath)"

Write-Host "`nDirectory Contents:" -ForegroundColor Yellow
if (Test-Path "/imagegeneration") {
    Write-Host "  /imagegeneration contents:"
    Get-ChildItem "/imagegeneration" | ForEach-Object { Write-Host "    $_" }
    
    if (Test-Path "/imagegeneration/tests") {
        Write-Host "  /imagegeneration/tests contents:"
        Get-ChildItem "/imagegeneration/tests" | ForEach-Object { Write-Host "    $_" }
    }
    
    if (Test-Path "/imagegeneration/helpers") {
        Write-Host "  /imagegeneration/helpers contents:"
        Get-ChildItem "/imagegeneration/helpers" | ForEach-Object { Write-Host "    $_" }
    }
} else {
    Write-Host "  /imagegeneration directory does not exist" -ForegroundColor Red
}

Write-Host "`nTesting Module Import:" -ForegroundColor Yellow
try {
    Import-Module $helpersPath -Force
    Write-Host "  ✓ Successfully imported Helpers.psm1" -ForegroundColor Green
    
    # Test Get-ToolsetContent function
    try {
        $toolset = Get-ToolsetContent
        Write-Host "  ✓ Successfully called Get-ToolsetContent" -ForegroundColor Green
        Write-Host "  ✓ azureModules found: $($toolset.azureModules.Count) modules" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to call Get-ToolsetContent: $_" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Failed to import Helpers.psm1: $_" -ForegroundColor Red
}

Write-Host "`n=== Debug Complete ===" -ForegroundColor Cyan