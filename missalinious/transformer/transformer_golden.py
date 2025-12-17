import numpy as np

# ---------------- PARAMETERS ----------------
SEQ_LEN   = 4
EMBED_DIM = 8
HEADS     = 2
HEAD_DIM  = EMBED_DIM // HEADS

# ---------------- INPUT (MUST MATCH RTL) ----------------
x = np.zeros((SEQ_LEN, EMBED_DIM), dtype=np.int64)
for i in range(SEQ_LEN):
    for j in range(EMBED_DIM):
        x[i,j] = (i+1)*(j+2)

# Identity projections
Q = x.copy()
K = x.copy()
V = x.copy()

# ---------------- ATTENTION ----------------
attn_out = np.zeros_like(x)

for h in range(HEADS):
    for i in range(SEQ_LEN):
        for d in range(HEAD_DIM):
            acc = 0
            for j in range(SEQ_LEN):
                dot = 0
                for k in range(HEAD_DIM):
                    dot += Q[i,h*HEAD_DIM+k] * K[j,h*HEAD_DIM+k]
                acc += (dot >> 6) * V[j,h*HEAD_DIM+d]
            attn_out[i,h*HEAD_DIM+d] = acc

# ---------------- FFN (identity in RTL) ----------------
ffn_out = attn_out.copy()

# ---------------- RESIDUAL ----------------
y = x + attn_out + ffn_out

# ---------------- WRITE GOLDEN ----------------
with open("python_golden.txt","w") as f:
    for i in range(SEQ_LEN):
        for j in range(EMBED_DIM):
            f.write(f"{int(y[i,j])}\n")

print("Python golden written to python_golden.txt")

