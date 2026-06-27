def generate_mif_bcd(filename="address_mod.mif"):
    depth = 2048  # 2^11
    width = 16    # 4 hex digits

    with open(filename, "w") as f:
        # MIF Header
        f.write(f"WIDTH={width};\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=DEC;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")

        for addr in range(depth):
            quotient = addr // 60
            remainder = addr % 60
            
            # Formats as a 4-character string: 2 digits for quotient, 2 for remainder
            # Example: quotient 34, remainder 7 -> "3407"
            data_str = f"{quotient:02d}{remainder:02d}"
            
            f.write(f"    {addr} : {data_str};\n")

        f.write("END;\n")

if __name__ == "__main__":
    generate_mif_bcd("hex_to_mmss.mif")
    print("MIF file generated with BCD-style decimal formatting.")