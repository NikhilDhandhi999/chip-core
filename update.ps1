# update.ps1 - Run right inside C:\Users\nikhi\chip-core to pull the newest
# chip-core*.zip from Downloads, overwrite files in-place, and run the simulation!
$ErrorActionPreference = "Stop"

$latestZip = Get-ChildItem "$HOME\Downloads\chip-core*.zip" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latestZip) {
    Write-Host "ERROR: No chip-core*.zip found in $HOME\Downloads" -ForegroundColor Red
    exit 1
}

$parentDir = Split-Path -Parent (Get-Location)
Write-Host "Updating chip-core in-place from: $($latestZip.Name)..." -ForegroundColor Yellow
Expand-Archive -LiteralPath $latestZip.FullName -DestinationPath $parentDir -Force

powershell -ExecutionPolicy Bypass -File run.ps1
