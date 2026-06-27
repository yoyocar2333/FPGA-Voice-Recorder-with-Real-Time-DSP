import os

# --- Configuration ---
INPUT_FILE = 'lcd_data.txt'      # Your source text file
OUTPUT_FILE = 'lcd_data.mif'
ROM_DEPTH = 64                # Number of addresses in the memory
CHARS_PER_ADDR = 16           # 16 characters = 128 bits
ROM_WIDTH = CHARS_PER_ADDR * 8 # Total bits per address (128)

def ascii_to_mif():
    if not os.path.exists(INPUT_FILE):
        print(f"Error: {INPUT_FILE} not found.")
        return

    # Read all characters from the file
    with open(INPUT_FILE, 'r', encoding='ascii', errors='ignore') as f:
        data = f.read()

    # Convert characters to a list of hex strings (2 digits each)
    hex_data = [f"{ord(c):02X}" for c in data]
    
    total_chars = len(hex_data)
    required_addresses = (total_chars + CHARS_PER_ADDR - 1) // CHARS_PER_ADDR

    with open(OUTPUT_FILE, 'w') as f_out:
        # 1. Write MIF Header
        f_out.write(f"WIDTH={ROM_WIDTH};\n")
        f_out.write(f"DEPTH={ROM_DEPTH};\n")
        f_out.write("ADDRESS_RADIX=DEC;\n")
        f_out.write("DATA_RADIX=HEX;\n")
        f_out.write("CONTENT BEGIN\n")

        # 2. Process Addresses
        for i in range(ROM_DEPTH):
            start_idx = i * CHARS_PER_ADDR
            end_idx = start_idx + CHARS_PER_ADDR
            
            if start_idx < total_chars:
                # Slice the 16 characters for this address
                chunk = hex_data[start_idx:end_idx]
                
                # If chunk is shorter than 16, pad with '00'
                if len(chunk) < CHARS_PER_ADDR:
                    chunk += ['00'] * (CHARS_PER_ADDR - len(chunk))
                
                # Join characters into one long hex string
                # Note: Big-Endian format (first char at the most significant bit)
                chunk = reversed(chunk)
                data_word = "".join(chunk)
            else:
                # 3. Padding for unused addresses
                data_word = "0" * (ROM_WIDTH // 4)

            f_out.write(f"    {i} : {data_word};\n")

        f_out.write("END;\n")

    print(f"Success! {OUTPUT_FILE} created.")
    print(f"Total characters processed: {total_chars}")
    if required_addresses > ROM_DEPTH:
        print(f"Warning: Data truncated. Required {required_addresses} addresses, but depth is {ROM_DEPTH}.")

if __name__ == "__main__":
    ascii_to_mif()