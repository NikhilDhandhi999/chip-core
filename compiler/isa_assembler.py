"""
compiler/isa_assembler.py
Unified Tensor ISA Assembler & Dual-Workload UART Stream Compiler (chip-core v7.2)
Compiles two distinct AI programs to binary UART host packet streams:
  1. Fused Transformer Self-Attention Head -> build/uart_attn_stream.bin + build/gold_attn.hex
  2. Trained 1.58-Bit Ternary Vision Classifier -> build/uart_vision_stream.bin + build/gold_preds.txt
"""

import os
import math
import random

OPCODES = {
    "NOP":       0x0,
    "CLEAR_ACC": 0x1,
    "MATMUL":    0x2,
    "RELU":      0x3,
    "SOFTERMAX": 0x4,
    "STORE_ACC": 0x5,
    "ARGMAX":    0x6,
    "HALT":      0xF,
}

CLASS_NAMES = ["Digit '0'", "Digit '1'", "Symbol 'X'", "Symbol '+'"]
BASE_TEMPLATES = {
    0: [0, 1, 1, 0,  1, 0, 0, 1,  1, 0, 0, 1,  0, 1, 1, 0],
    1: [0, 1, 1, 0,  0, 0, 1, 0,  0, 0, 1, 0,  0, 1, 1, 1],
    2: [1, 0, 0, 1,  0, 1, 1, 0,  0, 1, 1, 0,  1, 0, 0, 1],
    3: [0, 1, 0, 0,  1, 1, 1, 0,  0, 1, 0, 0,  0, 0, 0, 0],
}

def encode_inst(op_name, dst=0, src_a=0, src_b=0,
                acc_keep=0, transpose_b=0, ternary=0, causal_mask=0, imm=0):
    op = OPCODES[op_name]
    flags = (
        ((acc_keep & 1) << 0)
        | ((transpose_b & 1) << 1)
        | ((ternary & 1) << 2)
        | ((causal_mask & 1) << 3)
    )
    return (
        ((op & 0xF) << 28)
        | ((dst & 0xF) << 24)
        | ((src_a & 0xF) << 20)
        | ((src_b & 0xF) << 16)
        | ((flags & 0xFF) << 8)
        | (imm & 0xFF)
    )

def build_uart_stream(inst_words, sram_bytes, include_read_preds=False):
    stream = bytearray()
    for addr, word in enumerate(inst_words):
        stream.append(0x01)
        stream.append(addr & 0xFF)
        stream.extend(word.to_bytes(4, byteorder="big"))

    for addr, val in enumerate(sram_bytes):
        stream.append(0x02)
        stream.append(addr & 0xFF)
        stream.append(val & 0xFF)

    stream.append(0x03)
    if include_read_preds:
        stream.append(0x04)
    return stream

def compile_self_attention():
    Q = [
        [ 4,  0, -4,  2],
        [ 0,  4,  2, -2],
        [-2,  2,  4,  0],
        [ 2, -2,  0,  4],
    ]
    K = [
        [ 4,  0, -4,  0],
        [ 0,  4,  2,  0],
        [-2,  4,  2,  0],
        [ 4, -2,  0,  4],
    ]
    V = [
        [ 1,  0, -1,  1],
        [ 0,  1,  1,  0],
        [-1,  1, -1,  1],
        [ 1, -1,  0,  1],
    ]

    S = [[sum(Q[r][k] * K[c][k] for k in range(4)) for c in range(4)] for r in range(4)]
    P = []
    for r in range(4):
        masked = [S[r][c] if c <= r else -999999 for c in range(4)]
        m = max(masked[c] for c in range(r + 1))
        u = []
        for c in range(4):
            if c > r:
                u.append(0)
            else:
                sh = max(0, (m - S[r][c]) >> 1)
                u.append(0 if sh >= 8 else (128 >> sh))
        rsum = sum(u)
        P.append([(val * 127) // rsum for val in u])

    O_gold = []
    for r in range(4):
        row_o = []
        for c in range(4):
            acc = sum(P[r][k] * V[k][c] for k in range(4))
            row_o.append(max(-128, min(127, acc)))
        O_gold.append(row_o)

    sram = [0] * 64
    for slot_id, mat in [(0, Q), (1, K), (2, V)]:
        for r in range(4):
            for c in range(4):
                sram[slot_id * 16 + r * 4 + c] = mat[r][c]

    prog = [
        encode_inst("MATMUL",    src_a=0, src_b=1, transpose_b=1),
        encode_inst("SOFTERMAX", dst=3, causal_mask=1, imm=1),
        encode_inst("MATMUL",    src_a=3, src_b=2, ternary=1),
        encode_inst("STORE_ACC", dst=4, imm=0),
        encode_inst("HALT"),
    ]

    with open("build/prog_attn.hex", "w", encoding="utf-8") as f:
        for w in prog:
            f.write(f"{w:08x}\n")

    with open("build/gold_attn.hex", "w", encoding="utf-8") as f:
        for r in range(4):
            for c in range(4):
                f.write(f"{O_gold[r][c] & 0xFF:02x}\n")

    stream = build_uart_stream(prog, sram, include_read_preds=False)
    with open("build/uart_attn_stream.bin", "wb") as fb:
        fb.write(stream)

    return prog, stream, O_gold

def ternarize_matrix(W, thresh=0.35):
    return [[1 if v > thresh else (-1 if v < -thresh else 0) for v in row] for row in W]

def make_sample(cls_id, rng):
    return [rng.randint(10, 14) if px == 1 else rng.randint(0, 2) for px in BASE_TEMPLATES[cls_id]]

def softmax_probs(logits):
    m = max(logits)
    exps = [math.exp(max(-20.0, min(20.0, (l - m) * 0.1))) for l in logits]
    s = sum(exps)
    return [e / s for e in exps]

def train_ternary_mlp():
    rng = random.Random(7)
    dataset = [(make_sample(c, rng), c) for _ in range(50) for c in range(4)]
    W1 = [[rng.uniform(-0.6, 0.6) for _ in range(4)] for _ in range(16)]
    W2 = [[rng.uniform(-0.6, 0.6) for _ in range(4)] for _ in range(4)]

    lr = 0.02
    for _ in range(150):
        rng.shuffle(dataset)
        for x, target in dataset:
            W1_q = ternarize_matrix(W1)
            W2_q = ternarize_matrix(W2)
            z1 = [sum(x[i] * W1_q[i][h] for i in range(16)) for h in range(4)]
            h_act = [max(0, z) >> 2 for z in z1]
            logits = [sum(h_act[h] * W2_q[h][c] for h in range(4)) for c in range(4)]
            probs = softmax_probs(logits)
            d_logits = [probs[c] - (1.0 if c == target else 0.0) for c in range(4)]

            d_h = [0.0] * 4
            for h in range(4):
                for c in range(4):
                    if h_act[h] > 0:
                        W2[h][c] = max(-1.0, min(1.0, W2[h][c] - lr * d_logits[c] * (h_act[h] / 10.0)))
                    d_h[h] += d_logits[c] * W2_q[h][c]

            for i in range(16):
                if x[i] > 0:
                    for h in range(4):
                        gate = 1.0 if z1[h] > 0 else 0.2
                        W1[i][h] = max(-1.0, min(1.0, W1[i][h] - lr * d_h[h] * gate * (x[i] / 12.0)))

    return ternarize_matrix(W1), ternarize_matrix(W2)

def compile_vision_classifier():
    W1_q, W2_q = train_ternary_mlp()
    eval_rng = random.Random(2026)
    test_images = [make_sample(c, eval_rng) for c in range(4)]

    slots = {}
    for t in range(4):
        slots[t]     = [[test_images[img][t*4 + k] for k in range(4)] for img in range(4)]
        slots[4 + t] = [[W1_q[t*4 + k][h] for h in range(4)] for k in range(4)]
    slots[9] = W2_q

    sram = [0] * 160
    for slot_id, mat4x4 in slots.items():
        for r in range(4):
            for c in range(4):
                sram[slot_id * 16 + r * 4 + c] = mat4x4[r][c]

    prog = [
        encode_inst("MATMUL", src_a=0, src_b=4, acc_keep=0, ternary=1),
        encode_inst("MATMUL", src_a=1, src_b=5, acc_keep=1, ternary=1),
        encode_inst("MATMUL", src_a=2, src_b=6, acc_keep=1, ternary=1),
        encode_inst("MATMUL", src_a=3, src_b=7, acc_keep=1, ternary=1),
        encode_inst("RELU",   dst=8, imm=2),
        encode_inst("MATMUL", src_a=8, src_b=9, acc_keep=0, ternary=1),
        encode_inst("ARGMAX"),
        encode_inst("HALT"),
    ]

    with open("build/prog_vision.hex", "w", encoding="utf-8") as f:
        for w in prog:
            f.write(f"{w:08x}\n")

    with open("build/sram_vision.hex", "w", encoding="utf-8") as f:
        for val in sram:
            f.write(f"{val & 0xFF:02x}\n")

    preds_gold = []
    for img in range(4):
        x = test_images[img]
        z1 = [sum(x[i] * W1_q[i][h] for i in range(16)) for h in range(4)]
        h_vec = [min(127, max(0, z) >> 2) for z in z1]
        logits = [sum(h_vec[h] * W2_q[h][c] for h in range(4)) for c in range(4)]
        preds_gold.append(max(range(4), key=lambda c: logits[c]))

    with open("build/gold_preds.txt", "w", encoding="utf-8") as f:
        f.write(" ".join(str(p) for p in preds_gold) + "\n")

    stream = build_uart_stream(prog, sram, include_read_preds=True)
    with open("build/uart_vision_stream.bin", "wb") as fb:
        fb.write(stream)

    return prog, stream, preds_gold

def main():
    os.makedirs("build", exist_ok=True)
    p_attn, s_attn, o_gold = compile_self_attention()
    p_vis, s_vis, preds_gold = compile_vision_classifier()

    print("=== Dual-Workload Tensor ISA Assembler & UART Stream Compiler (chip-core v7.2) ===")
    print(f"[Workload 1: Transformer Self-Attention] {len(p_attn)} insts | {len(s_attn)}B UART stream")
    print(f"[Workload 2: 1.58-Bit Vision Classifier]  {len(p_vis)} insts | {len(s_vis)}B UART stream | Expected: {[CLASS_NAMES[p] for p in preds_gold]}")

if __name__ == "__main__":
    main()
