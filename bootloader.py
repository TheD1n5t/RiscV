import struct

with open("uart_spam.bin", "rb") as f:
    payload = f.read()

packet = b"\x55\xAA" + struct.pack("<I", len(payload)) + payload

with open("uart_spam_boot.bin", "wb") as f:
    f.write(packet)