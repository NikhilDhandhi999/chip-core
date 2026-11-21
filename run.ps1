# run.ps1 - End-to-End Compiler + RTL Simulation + Yosys Synthesis + PPA Report (v7.0)
$ErrorActionPreference = "Stop"

if (Test-Path "VERSION.txt") {
    $ver = (Get-Content "VERSION.txt" -Raw).Trim()
    Write-Host "Running chip-core ($ver)" -ForegroundColor Green
}

$roots = @("C:\iverilog", "C:\Program Files\iverilog", "C:\Program Files (x86)\iverilog", "$env:LOCALAPPDATA\Programs\iverilog", "C:\oss-cad-suite", "$env:LOCALAPPDATA\Microsoft\WinGet\Links")
$dirs = $roots | ForEach-Object { @($_, "$_\bin", "$_\gtkwave\bin") } | Where-Object { Test-Path $_ }
foreach ($d in $dirs) {
    if ($env:Path -notlike "*$d*") { $env:Path = "$env:Path;$d" }
}

if (!(Test-Path "build")) { New-Item -ItemType Directory -Path "build" | Out-Null }

Write-Host "[1/4] Compiling Tensor ISA program, SRAM slots & UART binary stream..." -ForegroundColor Cyan
python compiler/isa_assembler.py

Write-Host "[2/4] Compiling UART Serial Host Bridge + Unified Processor RTL..." -ForegroundColor Cyan
iverilog -o build/chip_sim.vvp rtl/mac_pe.v rtl/systolic_array_4x4.v rtl/relu_unit.v rtl/softermax_unit.v rtl/argmax_unit.v rtl/instruction_decoder.v rtl/uart_rx.v rtl/uart_tx.v rtl/uart_host_bridge.v rtl/ai_chip_synth_top.v rtl/ai_chip_top.v tb/tb_ai_chip_top.v

Write-Host "[3/4] Running bit-level 8N1 UART serial simulation & readback check..." -ForegroundColor Cyan
vvp build/chip_sim.vvp

if (Get-Command "yosys" -ErrorAction SilentlyContinue) {
    Write-Host "[Synth] Yosys detected! Synthesizing CMOS gate-level netlist -> build/ai_chip_netlist.v..." -ForegroundColor Green
    yosys -s synth/synth.ys | Out-File -FilePath "build/yosys_synth.log" -Encoding utf8
}

Write-Host "[4/4] Generating Silicon Gate-Level Synthesis & PPA Report..." -ForegroundColor Cyan
python compiler/analyze_silicon.py
