# make_hex.py
import sys

if len(sys.argv) != 3:
    print("Usage: python make_hex.py main.bin payload_mytest.hex")
    sys.exit(1)

bin_file = sys.argv[1]
hex_file = sys.argv[2]

with open(bin_file, "rb") as f_in, open(hex_file, "w") as f_out:
    data = f_in.read()
    for b in data:
        f_out.write(f"{b:02x}\n")
