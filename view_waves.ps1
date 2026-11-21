# view_waves.ps1 - Opens GTKWave with pre-loaded systolic array & UART signals
$ErrorActionPreference = "Stop"

$roots = @("C:\iverilog", "C:\Program Files\iverilog", "C:\oss-cad-suite")
$dirs = $roots | ForEach-Object { @("$_in", "$_\gtkwave\bin") } | Where-Object { Test-Path $_ }
foreach ($d in $dirs) {
    if ($env:Path -notlike "*$d*") { $env:Path = "$env:Path;$d" }
}

if (-not (Test-Path "build/chip_core.vcd")) {
    Write-Host "VCD waveform not found — running simulation first..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File run.ps1
}

if (Get-Command "gtkwave" -ErrorAction SilentlyContinue) {
    Start-Process "gtkwave" -ArgumentList "build/chip_core.vcd", "tb/chip_core.gtkw"
} else {
    Write-Host "GTKWave not found in PATH. Install Icarus Verilog (with GTKWave) or OSS CAD Suite." -ForegroundColor Red
}
