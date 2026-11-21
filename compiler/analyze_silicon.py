"""
compiler/analyze_silicon.py
Evidence-Separated Gate-Level Synthesis & Silicon PPA Report (chip-core v7.2)
Parses Yosys 0.71+ synthesis logs (top-level ai_chip_top summary) and simulation telemetry.
"""

import os
import re

def parse_telemetry():
    path = "build/sim_telemetry.txt"
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        parts = f.read().strip().split()
        if len(parts) >= 8:
            return [int(x) for x in parts[:8]]
    return None

def get_top_stat_block(log_path):
    if not os.path.exists(log_path):
        return None
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    blocks = re.split(r"===\s+[^=]+\s+===", text)
    return blocks[-1] if blocks else text

def parse_yosys_cmos():
    block = get_top_stat_block("build/yosys_synth.log")
    if not block:
        return None
    m_cells = re.search(r"(\d+)\s+cells", block)
    m_wires = re.search(r"(\d+)\s+wires", block)
    dff_matches = re.findall(r"(\d+)\s+\$_[A-Z]*DFF[^\s]*", block)
    total_dffs = sum(int(x) for x in dff_matches) if dff_matches else 0
    if m_cells:
        return int(m_cells.group(1)), (int(m_wires.group(1)) if m_wires else 0), total_dffs
    return None

def parse_yosys_xilinx():
    block = get_top_stat_block("build/yosys_xilinx.log")
    if not block:
        return None
    lut_matches = re.findall(r"(\d+)\s+LUT[1-6]", block)
    fd_matches = re.findall(r"(\d+)\s+FD[A-Z]+", block)
    dsp_matches = re.findall(r"(\d+)\s+DSP48E1", block)
    if lut_matches:
        return (
            sum(int(x) for x in lut_matches),
            sum(int(x) for x in fd_matches),
            sum(int(x) for x in dsp_matches),
        )
    return None

def main():
    telem = parse_telemetry()
    cmos_stats = parse_yosys_cmos()
    xilinx_stats = parse_yosys_xilinx()

    print("==========================================================================")
    print("  CHIP-CORE v7.2 - EVIDENCE-SEPARATED PPA & VERIFICATION REPORT")
    print("==========================================================================")
    print("Top Synthesizable Module : rtl/ai_chip_top.v (UART Bridge + Tensor ISA SoC)")
    print("")
    print("[A] DIRECTLY MEASURED SIMULATION & SYNTHESIS METRICS")
    print("--------------------------------------------------------------------------")

    if cmos_stats:
        cells, wires, dffs = cmos_stats
        print(f"  Yosys CMOS Cells       : {cells:,} mapped logic & sequential cells (measured)")
        print(f"  Yosys Flip-Flops       : {dffs:,} DFF primitives (measured)")
        print(f"  Yosys Internal Nets    : {wires:,} wires (measured)")
    else:
        print("  Yosys CMOS Synthesis   : Not yet run (see build/yosys_synth.log)")

    if xilinx_stats:
        luts, fds, dsps = xilinx_stats
        print(f"  Xilinx 7-Series LUTs   : {luts:,} LUTs + {fds:,} FFs + {dsps} DSP48E1 (measured via Yosys)")
    else:
        print("  Xilinx 7-Series LUTs   : Not yet run (see build/yosys_xilinx.log)")

    if telem:
        attn_cyc, attn_skip, attn_byp, attn_ok, vis_cyc, vis_skip, vis_byp, vis_ok = telem
        print(f"  Workload 1 (Attention) : {attn_cyc} cycles | {attn_skip} zero-skips | {attn_byp} ternary ops | {'PASS' if attn_ok else 'FAIL'}")
        print(f"  Workload 2 (Vision)    : {vis_cyc} cycles | {vis_skip} zero-skips | {vis_byp} ternary ops | {'PASS' if vis_ok else 'FAIL'}")

    print("")
    print("[B] ANALYTICAL ARCHITECTURAL ESTIMATES (REQUIRES PHYSICAL / STA / POWER TOOLS)")
    print("--------------------------------------------------------------------------")
    print("  Target Fmax (650 MHz)  : Analytical estimate @ 28nm (requires post-P&R STA)")
    print("  Silicon Area (28nm)    : ~0.0075 mm^2 analytical cell density estimate (requires PDK layout)")
    print("  Ternary Energy Savings : Analytical MAC-vs-Add switching model (requires VCD power sim)")
    print("==========================================================================")

if __name__ == "__main__":
    main()
