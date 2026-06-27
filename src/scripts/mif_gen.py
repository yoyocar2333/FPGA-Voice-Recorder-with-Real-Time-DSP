import struct
import os

# --- 設定區 ---
INPUT_FILE = '[bilibili]全群星最忧郁的两人.raw'    # 你從 Audacity 匯出的檔案
OUTPUT_FILE = '[bilibili]全群星最忧郁的两人.mif'
ROM_DEPTH = 65536           # 2的16次方，對應 16-bit 地址線
ROM_WIDTH = 16              # 16-bit 數據寬度

def generate_mif():
    if not os.path.exists(INPUT_FILE):
        print(f"錯誤：找不到 {INPUT_FILE}，請確認檔案在同一個資料夾。")
        return

    file_size = os.path.getsize(INPUT_FILE)
    actual_samples = file_size // 2
    print(f"偵測到檔案大小: {file_size} bytes ({actual_samples} 個採樣點)")

    max = 0
    min = 0

    with open(INPUT_FILE, 'rb') as f_in, open(OUTPUT_FILE, 'w') as f_out:
        # 1. 寫入 MIF 檔頭
        f_out.write(f"WIDTH={ROM_WIDTH};\n")
        f_out.write(f"DEPTH={ROM_DEPTH};\n")
        f_out.write("ADDRESS_RADIX=DEC;\n")
        f_out.write("DATA_RADIX=HEX;\n")
        f_out.write("CONTENT BEGIN\n")

        # 2. 轉換數據
        for i in range(ROM_DEPTH):
            if i < actual_samples:
                raw_data = f_in.read(2)
                if len(raw_data) < 2: # 預防檔案結尾不到 2 bytes
                    val = 0
                else:
                    # '<h' 代表 Little-endian signed short
                    # 如果燒出來聲音不對，把 '<h' 改成 '>h' (Big-endian)
                    val = struct.unpack('<h', raw_data)[0]
            else:
                # 3. 補零 (Padding)
                val = 0

            if (val > max): max = val
            if (val < min): min = val
            
            # 將數值轉為 4 位 16 進位，並處理負數 (val & 0xFFFF)
            f_out.write(f"    {i} : {val & 0xFFFF:04X};\n")

        f_out.write("END;\n")
    
    print(f"成功！已產出 {OUTPUT_FILE}")
    print(f"Max = {max}, min = {min}.")
    if actual_samples > ROM_DEPTH:
        print(f"警告：音訊點數 ({actual_samples}) 超過 ROM 深度 ({ROM_DEPTH})，尾部已被截斷。")
    print("Thank you...")

if __name__ == "__main__":
    generate_mif()