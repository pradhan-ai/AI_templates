import numpy as np

LEN = 8

# Q8.8 input
x = np.array([10, 20, 30, 40, 50, 60, 70, 80], dtype=np.int32) << 8

# Mean
mean = np.sum(x) // LEN

# Variance
diff = x - mean
var = np.sum(diff * diff) // LEN  # Q16.16

# rsqrt LUT
def rsqrt_lut(var):
    idx = var >> 12
    idx = max(1, min(16, idx))
    lut = {
        1:65535,2:46340,3:37837,4:32768,
        5:29309,6:26755,7:24606,8:23170,
        9:21845,10:20724,11:19727,12:18868,
        13:18096,14:17476,15:16861,16:16384
    }
    return lut[idx]

inv_std = rsqrt_lut(var >> 16)

# Normalize
y = ((x - mean) * inv_std) >> 16

print("Input:", x >> 8)
print("Mean:", mean >> 8)
print("Output Q8.8:", y >> 8)

