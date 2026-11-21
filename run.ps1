# run.ps1 - End-to-End Compiler + Dual-Workload Simulation + Yosys Synthesis + PPA Report (v7.2)
$ErrorActionPreference = "Stop"

if (Test-Path "VERSION.txt") {
    $ver = (Get-Content "VERSION.txt" -Raw).Trim()
    Write-Host "Running chip-core ($ver)" -ForegroundColor Green
}

$roots = @("C:\iverilog", "C:\Program Files\iverilog", "C:\Program Files (x86)\iverilog", "$env:LOCALAPPDATA\Programs\iverilog", "C:\oss-cad-suite")
$dirs = $roots | ForEach-Object { @($_, "$_\bin", "$_\gtkwave\bin") } | Where-Object { Test-Path $_ }
foreach ($d in $dirs) {
    if ($env:Path -notlike "*$d*") { $env:Path = "$env:Path;$d" }
}

if (!(Test-Path "build")) { New-Item -ItemType Directory -Path "build" | Out-Null }

Write-Host "[1/4] Compiling Dual-Workload Tensor ISA programs & UART binary streams..." -ForegroundColor Cyan
python compiler/isa_assembler.py

Write-Host "[2/4] Compiling UART Serial Host Bridge + Unified Processor RTL..." -ForegroundColor Cyan
iverilog -o build/chip_sim.vvp rtl/mac_pe.v rtl/systolic_array_4x4.v rtl/relu_unit.v rtl/softermax_unit.v rtl/argmax_unit.v rtl/instruction_decoder.v rtl/uart_rx.v rtl/uart_tx.v rtl/uart_host_bridge.v rtl/ai_chip_synth_top.v rtl/ai_chip_top.v tb/tb_ai_chip_top.v

Write-Host "[3/4] Running bit-level 8N1 UART dual-workload simulation (Attention + Vision)..." -ForegroundColor Cyan
vvp build/chip_sim.vvp

if (Test-Path "C:\oss-cad-suite\environment.bat") {
    Write-Host "[Synth 1/2] Synthesizing CMOS gate-level netlist via Yosys..." -ForegroundColor Green
    cmd /c "call C:\oss-cad-suite\environment.bat && yosys -s synth/synth.ys" | Out-File -FilePath "build/yosys_synth.log" -Encoding utf8
    Write-Host "[Synth 2/2] Synthesizing Xilinx Artix-7 LUT/FF mapping via Yosys..." -ForegroundColor Green
    cmd /c "call C:\oss-cad-suite\environment.bat && yosys -s synth/synth_xilinx.ys" | Out-File -FilePath "build/yosys_xilinx.log" -Encoding utf8
} elseif (Get-Command "yosys" -ErrorAction SilentlyContinue) {
    Write-Host "[Synth 1/2] Synthesizing CMOS gate-level netlist via Yosys..." -ForegroundColor Green
    yosys -s synth/synth.ys | Out-File -FilePath "build/yosys_synth.log" -Encoding utf8
    Write-Host "[Synth 2/2] Synthesizing Xilinx Artix-7 LUT/FF mapping via Yosys..." -ForegroundColor Green
    yosys -s synth/synth_xilinx.ys | Out-File -FilePath "build/yosys_xilinx.log" -Encoding utf8
}

Write-Host "[4/4] Generating Evidence-Separated Silicon PPA Report..." -ForegroundColor Cyan
python compiler/analyze_silicon.py
