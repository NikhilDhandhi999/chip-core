# synth/install_yosys.ps1 - Installs Yosys Open-Source Synthesis Suite on Windows via winget/scoop
$ErrorActionPreference = "Stop"

Write-Host "Checking for Yosys..." -ForegroundColor Cyan
if (Get-Command "yosys" -ErrorAction SilentlyContinue) {
    Write-Host "Yosys is already installed!" -ForegroundColor Green
    yosys -V
    exit 0
}

if (Get-Command "winget" -ErrorAction SilentlyContinue) {
    Write-Host "Installing YosysHQ OSS CAD Suite via winget..." -ForegroundColor Yellow
    winget install --id YosysHQ.OSS-CAD-Suite -e --accept-source-agreements --accept-package-agreements
} elseif (Get-Command "scoop" -ErrorAction SilentlyContinue) {
    Write-Host "Installing Yosys via scoop..." -ForegroundColor Yellow
    scoop install yosys
} else {
    Write-Host "Download OSS CAD Suite for Windows from: https://github.com/YosysHQ/oss-cad-suite-build/releases" -ForegroundColor Yellow
    Write-Host "Extract to C:\oss-cad-suite and re-run run.ps1!" -ForegroundColor Yellow
}
