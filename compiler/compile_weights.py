"""
compiler/compile_weights.py
Transformer Self-Attention Compiler for chip-core (v3.0):
- Compiles 4x4 Query (Q), Key (K), and Value (V) tensors into SRAM .hex images
- Computes exact golden reference for Fused Self-Attention:
    1. S = Q * K^T
    2. P = Softermax(CausalMask(S) >> scale_shift)   [Q0.7 INT8 in 0..127]
    3. O = (P * V) >> out_shift
"""

import os

def to_int8_hex(val: int) -> str:
    if not -128 <= val <= 127:
        raise ValueError(f"Value {val} out of INT8 range [-128, 127]")
    return f"{val & 0xFF:02x}"

def matmul_q_kt(Q, K):
    S = [[0]*4 for _ in range(4)]
    for r in range(4):
        for c in range(4):
            S[r][c] = sum(Q[r][k] * K[c][k] for k in range(4))
    return S

def matmul_4x4(A, B):
    C = [[0]*4 for _ in range(4)]
    for r in range(4):
        for c in range(4):
            C[r][c] = sum(A[r][k] * B[k][c] for k in range(4))
    return C

def hardware_softermax(S, causal_mask_en=1, scale_shift=1):
    P = [[0]*4 for _ in range(4)]
    for r in range(4):
        unmasked = [S[r][c] for c in range(4) if not (causal_mask_en and c > r)]
        max_val = max(unmasked)
        u = [0]*4
        for c in range(4):
            if causal_mask_en and c > r:
                u[c] = 0
            else:
                diff = max_val - S[r][c]
                sh = 0 if diff <= 0 else (diff >> scale_shift)
                u[c] = 0 if sh >= 8 else (128 >> sh)
        row_sum = sum(u)
        for c in range(4):
            P[r][c] = (u[c] * 127) // row_sum
    return P

def write_hex_matrix(filepath, mat):
    with open(filepath, "w", encoding="utf-8") as f:
        for row in mat:
            for val in row:
                f.write(to_int8_hex(val) + "\n")

def main():
    os.makedirs("build", exist_ok=True)

    causal_mask_en = 1  # 1 = GPT-style causal autoregressive mask, 0 = bidirectional
    ternary_v_mode = 1  # 1 = 1.58-Bit Ternary V weights {-1, 0, +1}, 0 = Standard INT8 V
    scale_shift    = 1  # Divide score delta by 2^1 (= sqrt(d_k=4))
    out_shift      = 7  # Divide by 128 (2^7) to convert Q0.7 probabilities back to token scale

    # 4 Tokens x 4 Head Dimensions (INT8)
    Q = [
        [ 3,  1, -2,  2],
        [ 2,  4,  0, -1],
        [-1,  3,  3,  1],
        [ 4, -2,  2,  3]
    ]

    K = [
        [ 2,  1, -1,  2],
        [ 1,  3,  1, -1],
        [ 0,  2,  3,  1],
        [ 3, -1,  2,  2]
    ]

    # Value Matrix V (4x4 Ternary {-1, 0, +1} for multiplier-free Pass 2)
    V = [
        [ 1,  0, -1,  1],
        [-1,  1,  1,  0],
        [ 0,  1, -1,  1],
        [ 1, -1,  0,  1]
    ]

    write_hex_matrix("build/q_matrix.hex", Q)
    write_hex_matrix("build/k_matrix.hex", K)
    write_hex_matrix("build/v_matrix.hex", V)

    S_gold = matmul_q_kt(Q, K)
    P_gold = hardware_softermax(S_gold, causal_mask_en=causal_mask_en, scale_shift=scale_shift)
    O_raw  = matmul_4x4(P_gold, V)
    O_int8 = [[max(-128, min(127, O_raw[r][c] >> out_shift)) for c in range(4)] for r in range(4)]

    with open("build/golden_expected.txt", "w", encoding="utf-8") as f:
        flat_raw = [str(O_raw[r][c]) for r in range(4) for c in range(4)]
        f.write(f"{causal_mask_en} {ternary_v_mode} {scale_shift} {out_shift} " + " ".join(flat_raw) + "\n")

    print("=== Transformer Self-Attention Compiler (chip-core v3.0) ===")
    print(f"Attention Mode       : {'Causal Autoregressive (GPT)' if causal_mask_en else 'Bidirectional (Encoder)'}")
    print(f"Value Datapath       : {'1.58-Bit Ternary V (Multiplier-Free)' if ternary_v_mode else 'Standard INT8 V'}")
    print("Golden Attention Scores S = Q * K^T:")
    for row in S_gold:
        print("  ", row)
    print("Golden Causal Softermax P (Q0.7 INT8 [0..127]):")
    for row in P_gold:
        print("  ", row)
    print("Golden Attention Output O_raw = P * V:")
    for row in O_raw:
        print("  ", row)
    print("Golden Scaled Output O_int8 = O_raw >> out_shift:")
    for row in O_int8:
        print("  ", row)

if __name__ == "__main__":
    main()
