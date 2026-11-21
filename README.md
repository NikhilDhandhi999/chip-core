# `chip-core` — Custom 1.58-Bit Ternary & Transformer AI Accelerator SoC

[![RTL](https://img.shields.io/badge/RTL-Synthesizable_Verilog-blue.svg)]()
[![ISA](https://img.shields.io/badge/ISA-32--Bit_Tensor_ISA-purple.svg)]()
[![Precision](https://img.shields.io/badge/Compute-1.58--Bit_Ternary_%7B--1%2C0%2C%2B1%7D-green.svg)]()
[![Interface](https://img.shields.io/badge/Host_I%2FO-8N1_UART_Serial_Bridge-orange.svg)]()

`chip-core` is an end-to-end, synthesizable **AI Accelerator System-on-Chip (SoC)** written in pure Verilog RTL with a custom Python Quantization-Aware Trainer, 32-Bit Tensor ISA Assembler, UART Host Serial Bridge, and Gate-Level Synthesis flow.

---

## Architecture Overview

```text
  Host PC (Python / PySerial)
       │  8N1 UART Serial (WRITE_INST, WRITE_SRAM, RUN_EXEC, READ_PREDS)
       ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  ai_chip_top (UART-Enabled Programmable AI SoC)                            │
│                                                                            │
│  ┌──────────────────────┐       ┌───────────────────────────────────────┐  │
│  │  uart_host_bridge    │──────▶│  32x32b Instruction RAM + Decoder     │  │
│  │  (uart_rx / uart_tx) │       │  (MATMUL, RELU, SOFTERMAX, ARGMAX)    │  │
│  └──────────────────────┘       └───────────────────┬───────────────────┘  │
│                                                     │                      │
│  ┌──────────────────────────────────────────────────▼───────────────────┐  │
│  │  256-Byte Unified Tensor Scratchpad SRAM (16 Slots x 4x4 INT8)       │  │
│  └──────────────────┬───────────────────────────────────────────────────┘  │
│                     │ Skewed Wavefront Feeder (with Zero-Copy Transpose)   │
│  ┌──────────────────▼───────────────────────────────────────────────────┐  │
│  │  4x4 Output-Stationary Systolic Array (16 Dual-Mode Zero-Skip PEs)   │  │
│  │   • Mode 0: Standard INT8 MAC                                        │  │
│  │   • Mode 1: 1.58-Bit Ternary {-1, 0, +1} (100% Multiplier-Free)      │  │
│  └──────────────────┬───────────────────────────────────────────────────┘  │
│                     │                                                      │
│  ┌──────────────────▼───────────────────────────────────────────────────┐  │
│  │  Vector Post-Processors: Hardware ReLU | Causal Softermax | Argmax   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Hardware Features

1. **Dual-Mode Zero-Skipping Systolic Array (`rtl/mac_pe.v`, `rtl/systolic_array_4x4.v`):**
   - Hardware zero-skipping gates idle MAC clocks whenever an activation or weight is `0` (**70.9% zero-skip rate** on vision workloads).
   - **1.58-Bit Ternary Datapath (`{-1, 0, +1}`)** bypasses `8×8` multipliers completely using pure add/subtract logic (**13.0× lower compute energy** per batch).
2. **32-Bit Tensor ISA & Instruction Decoder (`rtl/instruction_decoder.v`, `compiler/isa_assembler.py`):**
   - Programmable fetch/decode/execute engine supporting `NOP`, `CLEAR_ACC`, `MATMUL` (with multi-tile accumulation `acc_keep` and zero-copy `transpose_b`), `RELU`, `SOFTERMAX`, `STORE_ACC`, `ARGMAX`, and `HALT`.
   - Executes **Fused Transformer Self-Attention** (`34 cycles`) and a **Trained 1.58-Bit Ternary Vision Classifier** (`70 cycles`) on the exact same silicon core.
3. **Fused Causal Softermax & Hardware Argmax (`rtl/softermax_unit.v`, `rtl/argmax_unit.v`):**
   - Replaces floating-point `exp(x)` with base-2 bit-shifts (`2^(-delta) = 128 >> delta`) and autoregressive causal masking (`col > row`).
   - Combinational comparator trees output winning class IDs directly on hardware pins.
4. **Synthesizable 8N1 UART Serial Host Bridge (`rtl/uart_rx.v`, `rtl/uart_tx.v`, `rtl/uart_host_bridge.v`):**
   - Streams instructions (`0x01`) and tensor data (`0x02`) from a host PC over serial RX, executes on silicon (`0x03`), and transmits predictions back over serial TX (`0x04`).

---

## Quick Start (Windows PowerShell)

```powershell
# 1. Run end-to-end compilation, bit-level UART simulation, and PPA report
powershell -ExecutionPolicy Bypass -File run.ps1

# 2. (Optional) Install Yosys for real CMOS gate-level netlist synthesis
powershell -ExecutionPolicy Bypass -File synth/install_yosys.ps1

# 3. Publish repository to GitHub (requires GitHub CLI `gh`)
powershell -ExecutionPolicy Bypass -File publish_github.ps1
```

---

## Silicon PPA Summary (`ai_chip_top` v7.0)

| Metric | Value |
| :--- | :--- |
| **Total Sequential Registers** | `4,741` flip-flops |
| **Logic Gate Count** | `14,990` NAND2-equivalent gates |
| **Xilinx Artix-7 Footprint** | `~6,245` 6-LUTs (`<25%` of Digilent Arty A7-35T) |
| **Estimated Silicon Area** | `0.0075 mm²` @ 28nm CMOS (`333.1 µm²` @ 4nm) |
| **Target Clock Frequency** | `650 MHz` @ 28nm CMOS |
