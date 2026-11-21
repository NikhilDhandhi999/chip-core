"""
compiler/train_and_compile.py
Real Neural Network Trainer & Quantized Chip Compiler for chip-core (v4.0):
1. Generates a dataset of 4x4 pixel visual patterns across 4 classes:
     Class 0: Digit '0' (Ring / Loop)
     Class 1: Digit '1' (Vertical Stroke)
     Class 2: Symbol 'X' (Diagonal Cross)
     Class 3: Symbol '+' (Orthogonal Cross)
2. Trains a 2-Layer Neural Network (16 pixels -> 4 hidden -> 4 classes) from scratch
   using Quantization-Aware Training (QAT) with Straight-Through Estimator (STE)
   so all weights converge to exact 1.58-Bit Ternary values {-1, 0, +1}!
3. Tiles the 4x16 batch and 16x4 weights into 4x4 hardware SRAM images
4. Exports compiled .hex files + exact golden reference for Verilog verification
"""

import os
import math
import random

CLASS_NAMES = ["Digit '0'", "Digit '1'", "Symbol 'X'", "Symbol '+'"]

# Canonical 4x4 pixel templates (16 pixels per image)
BASE_TEMPLATES = {
    0: [ # Digit '0'
        0, 1, 1, 0,
        1, 0, 0, 1,
        1, 0, 0, 1,
        0, 1, 1, 0,
    ],
    1: [ # Digit '1'
        0, 1, 1, 0,
        0, 0, 1, 0,
        0, 0, 1, 0,
        0, 1, 1, 1,
    ],
    2: [ # Symbol 'X'
        1, 0, 0, 1,
        0, 1, 1, 0,
        0, 1, 1, 0,
        1, 0, 0, 1,
    ],
    3: [ # Symbol '+'
        0, 1, 0, 0,
        1, 1, 1, 0,
        0, 1, 0, 0,
        0, 0, 0, 0,
    ],
}

def ternarize_matrix(W, thresh=0.35):
    """1.58-bit quantization: maps clamped latent weights in [-1, 1] -> {-1, 0, +1}"""
    Wq = []
    for row in W:
        q_row = []
        for v in row:
            if v > thresh:
                q_row.append(1)
            elif v < -thresh:
                q_row.append(-1)
            else:
                q_row.append(0)
        Wq.append(q_row)
    return Wq

def make_sample(cls_id, rng, noisy=True):
    tpl = BASE_TEMPLATES[cls_id]
    img = []
    for px in tpl:
        if px == 1:
            val = rng.randint(10, 14) if noisy else 12
        else:
            val = rng.randint(0, 2) if noisy else 0
        img.append(val)
    return img

def softmax_probs(logits):
    m = max(logits)
    exps = [math.exp(max(-20.0, min(20.0, (l - m) * 0.1))) for l in logits]
    s = sum(exps)
    return [e / s for e in exps]

def train_ternary_mlp():
    """Trains a 16 -> 4 -> 4 neural network using Quantization-Aware Training (STE)."""
    rng = random.Random(7)

    # Build 200 noisy training samples
    dataset = []
    for _ in range(50):
        for cls_id in range(4):
            dataset.append((make_sample(cls_id, rng, noisy=True), cls_id))

    # Initialize latent weights near quantization thresholds so gradients flow immediately
    W1 = [[rng.uniform(-0.6, 0.6) for _ in range(4)] for _ in range(16)]
    W2 = [[rng.uniform(-0.6, 0.6) for _ in range(4)] for _ in range(4)]

    lr = 0.02
    for epoch in range(150):
        rng.shuffle(dataset)
        for x, target in dataset:
            W1_q = ternarize_matrix(W1)
            W2_q = ternarize_matrix(W2)

            # Forward pass with quantized ternary weights
            z1 = [sum(x[i] * W1_q[i][h] for i in range(16)) for h in range(4)]
            h_act = [max(0, z) >> 2 for z in z1]  # Matches hardware shift_l1 = 2
            logits = [sum(h_act[h] * W2_q[h][c] for h in range(4)) for c in range(4)]

            probs = softmax_probs(logits)
            d_logits = [probs[c] - (1.0 if c == target else 0.0) for c in range(4)]

            # Backprop into W2 & W1 via Straight-Through Estimator (STE)
            d_h = [0.0] * 4
            for h in range(4):
                for c in range(4):
                    if h_act[h] > 0:
                        W2[h][c] = max(-1.0, min(1.0, W2[h][c] - lr * d_logits[c] * (h_act[h] / 10.0)))
                    d_h[h] += d_logits[c] * W2_q[h][c]

            for i in range(16):
                if x[i] > 0:
                    for h in range(4):
                        # Leaky STE slope (0.2 when z1 <= 0) prevents dead hidden neurons
                        ste_gate = 1.0 if z1[h] > 0 else 0.2
                        W1[i][h] = max(-1.0, min(1.0, W1[i][h] - lr * d_h[h] * ste_gate * (x[i] / 12.0)))

    W1_q = ternarize_matrix(W1)
    W2_q = ternarize_matrix(W2)

    # Evaluate final quantized accuracy on 200 unseen noisy samples
    correct = 0
    for _ in range(50):
        for cls_id in range(4):
            x = make_sample(cls_id, rng, noisy=True)
            z1 = [sum(x[i] * W1_q[i][h] for i in range(16)) for h in range(4)]
            h_act = [max(0, z) >> 2 for z in z1]
            logits = [sum(h_act[h] * W2_q[h][c] for h in range(4)) for c in range(4)]
            pred = max(range(4), key=lambda c: logits[c])
            if pred == cls_id:
                correct += 1

    acc = (correct / 200.0) * 100.0
    return W1_q, W2_q, acc

def to_int8_hex(val: int) -> str:
    if not -128 <= val <= 127:
        raise ValueError(f"Value {val} out of INT8 range [-128, 127]")
    return f"{val & 0xFF:02x}"

def main():
    os.makedirs("build", exist_ok=True)
    W1_q, W2_q, test_acc = train_ternary_mlp()

    # Create 4 unseen noisy test images (1 per class) to run as a batch on our silicon
    eval_rng = random.Random(2026)
    test_images = [make_sample(cls_id, eval_rng, noisy=True) for cls_id in range(4)]
    shift_l1 = 2

    # Tile X (4x16) into 4 tiles of 4x4 (each tile holds 4 pixels for all 4 images)
    with open("build/x_tiles.hex", "w", encoding="utf-8") as fx:
        for t in range(4):
            for img_idx in range(4):
                for k in range(4):
                    fx.write(to_int8_hex(test_images[img_idx][t*4 + k]) + "\n")

    # Tile W1 (16x4) into 4 tiles of 4x4
    with open("build/w1_tiles.hex", "w", encoding="utf-8") as fw1:
        for t in range(4):
            for k in range(4):
                for h in range(4):
                    fw1.write(to_int8_hex(W1_q[t*4 + k][h]) + "\n")

    # Write W2 (4x4)
    with open("build/w2_matrix.hex", "w", encoding="utf-8") as fw2:
        for h in range(4):
            for c in range(4):
                fw2.write(to_int8_hex(W2_q[h][c]) + "\n")

    # Compute exact golden reference for hardware verification
    H_gold = []
    Y_gold = []
    preds_gold = []
    for img_idx in range(4):
        x = test_images[img_idx]
        z1 = [sum(x[i] * W1_q[i][h] for i in range(16)) for h in range(4)]
        h_vec = [min(127, max(0, z) >> shift_l1) for z in z1]
        logits = [sum(h_vec[h] * W2_q[h][c] for h in range(4)) for c in range(4)]
        pred = max(range(4), key=lambda c: logits[c])
        H_gold.append(h_vec)
        Y_gold.append(logits)
        preds_gold.append(pred)

    with open("build/golden_expected.txt", "w", encoding="utf-8") as fg:
        flat_logits = [str(Y_gold[r][c]) for r in range(4) for c in range(4)]
        flat_preds  = [str(p) for p in preds_gold]
        fg.write(f"{shift_l1} " + " ".join(flat_preds) + " " + " ".join(flat_logits) + "\n")

    print("=== Quantization-Aware Neural Trainer & Chip Compiler (chip-core v4.0) ===")
    print(f"Architecture         : 16-Pixel Input -> 4 Hidden (ReLU) -> 4 Class Logits + Argmax")
    print(f"Weight Precision     : 1.58-Bit Ternary {{-1, 0, +1}} (100% Multiplier-Free!)")
    print(f"Unseen Test Accuracy : {test_acc:.1f}% (200 noisy 4x4 images)")
    print(f"Golden Test Predictions: {[CLASS_NAMES[p] for p in preds_gold]}")
    print("Compiled SRAM Tiles  -> build/x_tiles.hex, build/w1_tiles.hex, build/w2_matrix.hex")

if __name__ == "__main__":
    main()
