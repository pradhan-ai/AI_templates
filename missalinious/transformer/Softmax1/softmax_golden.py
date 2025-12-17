import numpy as np

# ---------------- PARAMETERS ----------------
N = 8

# Example input (Q8.8)
in_vec = np.array([
    1.5, 0.8, -0.2, 0.1, -1.0, 0.3, 0.0, -0.5
])

# Convert to Q8.8
in_fixed = (in_vec * 256).astype(np.int32)

# ---------------- STABLE SOFTMAX ----------------
max_val = np.max(in_fixed)

exp_vals = np.zeros(N, dtype=np.int64)

for i in range(N):
    shift = (in_fixed[i] - max_val) >> 8
    shift = max(min(shift, 0), -15)
    exp_vals[i] = 1 << (shift + 15)

exp_sum = np.sum(exp_vals)

# Q0.15 output
out = (exp_vals << 15) // exp_sum

# ---------------- PRINT ----------------
print("Input Q8.8:", in_fixed)
print("Exp vals  :", exp_vals)
print("Softmax Q0.15:", out)
print("Sum probs:", np.sum(out)/32768.0)

