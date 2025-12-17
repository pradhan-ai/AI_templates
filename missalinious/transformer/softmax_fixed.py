import numpy as np

# ---------------- PARAMETERS ----------------
LEN = 8

# Q8.8 input
inp = np.array([
    120, 80, 40, 0, -40, -80, -120, -160
], dtype=np.int32) << 8

# ---------------- EXP LUT ----------------
def exp_lut(x):
    idx = x >> 8
    idx = min(0, max(-8, idx))
    lut = {
        0: 65535,
        -1: 24109,
        -2: 8869,
        -3: 3265,
        -4: 1202,
        -5: 442,
        -6: 163,
        -7: 60,
        -8: 22
    }
    return lut[idx]

# ---------------- SOFTMAX ----------------
max_val = np.max(inp)

exp_vals = np.array([exp_lut(x - max_val) for x in inp], dtype=np.int64)
sum_exp = np.sum(exp_vals)

recip = (1 << 16) // sum_exp if sum_exp != 0 else 0
out = (exp_vals * recip) >> 16

print("Input Q8.8:", inp >> 8)
print("Exp Q0.16:", exp_vals)
print("Softmax Q0.16:", out)
print("Softmax float:", out / 65536.0)

