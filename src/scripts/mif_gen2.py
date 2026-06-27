import struct
import os

# --- 設定區 ---
INPUT_FILE = 'Por una Cabeza.raw'    # 你從 Audacity 匯出的檔案
OUTPUT_FILE = 'Por una Cabeza.mif'
ROM_DEPTH = 428856           # ?
ROM_WIDTH = 8                # 8-bit 數據寬度

def generate_mif():
    # Ensure these are defined: INPUT_FILE, OUTPUT_FILE, ROM_WIDTH=8, ROM_DEPTH
    
    if not os.path.exists(INPUT_FILE):
        print(f"錯誤：找不到 {INPUT_FILE}")
        return

    file_size = os.path.getsize(INPUT_FILE)
    # 8-bit = 1 byte per sample
    bytes_per_sample = 1 
    actual_samples = file_size // bytes_per_sample
    
    print(f"偵測到檔案大小: {file_size} bytes ({actual_samples} 個 8-bit 採樣點)")

    max = 0
    min = 0

    with open(INPUT_FILE, 'rb') as f_in, open(OUTPUT_FILE, 'w') as f_out:
        # 1. Header (Standard MIF format)
        f_out.write(f"WIDTH=8;\n") # Hardcoded to 8 for this version
        f_out.write(f"DEPTH={ROM_DEPTH};\n")
        f_out.write("ADDRESS_RADIX=DEC;\n")
        f_out.write("DATA_RADIX=HEX;\n")
        f_out.write("CONTENT BEGIN\n")

        # 2. Data Conversion
        for i in range(ROM_DEPTH):
            if i < actual_samples:
                raw_data = f_in.read(1)
                if not raw_data:
                    val = 0
                else:
                    # 'b' = signed char (8-bit)
                    # Use 'B' if your source data is unsigned (0-255)
                    val = struct.unpack('b', raw_data)[0]
            else:
                val = 0

            if (val > max): max = val
            if (val < min): min = val
            
            # Mask to 0xFF (8-bit) and format as 2-digit Hex
            f_out.write(f"    {i} : {val & 0xFF:02X};\n")

        f_out.write("END;\n")
    
    print(f"成功！已產出 {OUTPUT_FILE}")
    print(f"Max = {max}, min = {min}.")
    if actual_samples > ROM_DEPTH:
        print(f"警告：音訊點數 ({actual_samples}) 超過 ROM 深度 ({ROM_DEPTH})，尾部已被截斷。")
    print("Thank you...")

if __name__ == "__main__":
    generate_mif()