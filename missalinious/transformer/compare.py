rtl = np.loadtxt("rtl_output.txt", dtype=np.int64)
gold = np.loadtxt("python_golden.txt", dtype=np.int64)

if np.array_equal(rtl, gold):
    print("✅ PASS: RTL matches Python golden")
else:
    print("❌ FAIL: Mismatch detected")
    print("RTL :", rtl)
    print("GOLD:", gold)

