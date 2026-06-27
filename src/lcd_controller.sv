module lcd_controller (
    input wire clk_800k,    // 800 kHz clock (週期 1.25 us)
    input wire reset_n,     // Active-low reset (例如 KEY[0])
    input wire [17:0] SW,   // 指撥開關
    input wire [2:0] ext_state,
    input wire [3:0] speed,
    
    // LCD 介面
    output wire LCD_ON,
    output wire LCD_BLON,
    output wire LCD_RW,
    output reg  LCD_EN,
    output reg  LCD_RS,
    output reg  [7:0] LCD_DATA
);

    assign LCD_ON = 1'b1;
    assign LCD_BLON = 1'b0;
    assign LCD_RW = 1'b0; // 僅寫入

    // 狀態定義
    localparam S_INIT      = 3'd0;
    localparam S_LINE1_CMD = 3'd1;
    localparam S_SEND_CHAR = 3'd2;
    localparam S_LINE2_CMD = 3'd3;
    localparam S_WAIT_100K = 3'd4;

    reg [3:0]  state;
    reg [19:0] timer;      // 夠大以計數 1.53ms 或 125ms
    reg [3:0]  init_step;  // 追蹤初始化步驟
    reg [4:0]  char_idx;

    // ROM of string
    logic [7:0] string_rom [0:15], arg_rom[0:15]; logic [127:0] lcd_rom_data;
    always @(*) begin
        arg_rom[0] = SW[4]? "L": "C";
        arg_rom[1] = SW[4]? "i": "o";
        arg_rom[2] = SW[4]? "n": "n";
        arg_rom[3] = SW[4]? "e": "s";
        arg_rom[4] = SW[4]? "a": "t";
        arg_rom[5] = SW[4]? "r": " ";
        arg_rom[6] = " ";
        arg_rom[7] = "S";
        arg_rom[8] = "p";
        arg_rom[9] = "e";
        arg_rom[10] = "e";
        arg_rom[11] = "d";
        arg_rom[12] = ":";
        arg_rom[13] = SW[3]? " ": "1";
        arg_rom[14] = SW[3]? " ": "/";
        arg_rom[15] = 8'h30 + speed;
    end
    genvar i;
    generate
        for (i=0; i<16; i=i+1) begin : LCD_ROM_DATA_CONCAT
            assign string_rom[i] = lcd_rom_data[8*i +: 8];
        end
    endgenerate
    lcd_rom_wrapper X1(clk_800k, ext_state, SW, lcd_rom_data);

    // --- 字元對照表 (維持您的設計) ---
    reg [7:0] current_char; // [CRIT] Do not change this line.
    always @(*) begin
        current_char = char_idx[4]? arg_rom[char_idx[3:0]]: string_rom[char_idx[3:0]];
        // case(char_idx)
        //     // === 第一行內容 (固定字串) ===
        //     5'd0:  current_char = "H"; 
        //     5'd1:  current_char = "e"; 
        //     5'd2:  current_char = "l"; 
        //     5'd3:  current_char = "l";
        //     5'd4:  current_char = "o"; 
        //     5'd5:  current_char = " "; 
        //     5'd6:  current_char = "D"; 
        //     5'd7:  current_char = "E";
        //     5'd8:  current_char = "2"; 
        //     5'd9:  current_char = "-"; 
        //     5'd10: current_char = "1"; 
        //     5'd11: current_char = "1";
        //     5'd12: current_char = "5"; 
        //     5'd13: current_char = "!"; 
        //     5'd14: current_char = " "; 
        //     5'd15: current_char = " ";

        //     // === 第二行內容 (顯示 SW[7:0] 狀態) ===
        //     5'd16: current_char = "S"; 
        //     5'd17: current_char = "W"; 
        //     5'd18: current_char = " "; 
        //     5'd19: current_char = "V";
        //     5'd20: current_char = "a"; 
        //     5'd21: current_char = "l"; 
        //     5'd22: current_char = ":"; 
        //     5'd23: current_char = " ";
        //     // 動態轉換開關狀態為 ASCII 的 '1' 或 '0'
        //     5'd24: current_char = SW[7] ? "1" : "0";
        //     5'd25: current_char = SW[6] ? "1" : "0";
        //     5'd26: current_char = SW[5] ? "1" : "0";
        //     5'd27: current_char = SW[4] ? "1" : "0";
        //     5'd28: current_char = SW[3] ? "1" : "0";
        //     5'd29: current_char = SW[2] ? "1" : "0";
        //     5'd30: current_char = SW[1] ? "1" : "0";
        //     5'd31: current_char = SW[0] ? "1" : "0";
            
        //     default: current_char = " ";
        // endcase
    end

    // --- 主邏輯 ---
    always @(posedge clk_800k or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_INIT;
            timer <= 0;
            init_step <= 0;
            char_idx <= 0;
            LCD_EN <= 0;
            LCD_RS <= 0;
            LCD_DATA <= 8'h00;
        end else begin
            case (state)
                // ==========================================
                // 階段 1：硬體初始化 (嚴格時序控制)
                // ==========================================
                S_INIT: begin
                    case (init_step)
                        0: begin // Power-on 等待 > 15ms (以 1.25us 計算約需 12000 cycles)
                            if (timer < 12500) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd1};
                        end
                        1: begin // Function Set (8-bit)
                            LCD_RS <= 0; LCD_DATA <= 8'h38; LCD_EN <= 1;
                            init_step <= 2;
                        end
                        2: begin // 拉低 EN，等待 > 4.1ms (約 3280 cycles)
                            LCD_EN <= 0;
                            if (timer < 3500) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd3};
                        end
                        3: begin // Function Set (8-bit)
                            LCD_EN <= 1; init_step <= 4;
                        end
                        4: begin // 拉低 EN，等待 > 100us (約 80 cycles)
                            LCD_EN <= 0;
                            if (timer < 100) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd5};
                        end
                        5: begin // Function Set (8-bit, 雙行, 5x8 字體)
                            LCD_DATA <= 8'h38; LCD_EN <= 1; init_step <= 6;
                        end
                        6: begin // 拉低 EN，等待 40us
                            LCD_EN <= 0;
                            if (timer < 40) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd7};
                        end
                        7: begin // Display ON (隱藏游標)
                            LCD_DATA <= 8'h0C; LCD_EN <= 1; init_step <= 8;
                        end
                        8: begin // 拉低 EN，等待 40us
                            LCD_EN <= 0;
                            if (timer < 40) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd9};
                        end
                        9: begin // Display Clear
                            LCD_DATA <= 8'h01; LCD_EN <= 1; init_step <= 10;
                        end
                        10: begin // 拉低 EN，等待 > 1.53ms (清除螢幕需較長時間，約 1224 cycles)
                            LCD_EN <= 0;
                            if (timer < 1300) timer <= timer + 1;
                            else {timer, init_step} <= {20'd0, 4'd11};
                        end
                        11: begin // Entry Mode Set (自動右移)
                            LCD_DATA <= 8'h06; LCD_EN <= 1; init_step <= 12;
                        end
                        12: begin // 初始化結束，進入正常顯示循環
                            LCD_EN <= 0; 
                            state <= S_LINE1_CMD; 
                            timer <= 0;
                        end
                    endcase
                end

                // ==========================================
                // 階段 2：設定位址到第一行開頭 (0x80)
                // ==========================================
                S_LINE1_CMD: begin
                    if (timer == 0) begin
                        LCD_RS <= 0; LCD_DATA <= 8'h80; LCD_EN <= 1;
                        timer <= timer + 1;
                    end else if (timer == 1) begin
                        LCD_EN <= 0; // 製造 Enable 脈衝
                        timer <= timer + 1;
                    end else if (timer >= 40) begin // 確保滿足 40us 指令執行時間
                        state <= S_SEND_CHAR;
                        timer <= 0;
                        char_idx <= 0; // 從第 0 個字元開始寫
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // ==========================================
                // 階段 3：逐字發送字元到 LCD
                // ==========================================
                S_SEND_CHAR: begin
                    if (timer == 0) begin
                        LCD_RS <= 1; LCD_DATA <= current_char; LCD_EN <= 1;
                        timer <= timer + 1;
                    end else if (timer == 1) begin
                        LCD_EN <= 0;
                        timer <= timer + 1;
                    end else if (timer >= 40) begin // 每個字元執行時間約需 43us
                        timer <= 0;
                        if (char_idx == 15) begin
                            state <= S_LINE2_CMD; // 第一行寫完，準備換行
                        end else if (char_idx == 31) begin
                            state <= S_WAIT_100K; // 第二行寫完，進入休眠等待
                        end else begin
                            char_idx <= char_idx + 1; // 繼續寫下一個字
                        end
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // ==========================================
                // 階段 4：設定位址到第二行開頭 (0xC0)
                // ==========================================
                S_LINE2_CMD: begin
                    if (timer == 0) begin
                        LCD_RS <= 0; LCD_DATA <= 8'hC0; LCD_EN <= 1;
                        timer <= timer + 1;
                    end else if (timer == 1) begin
                        LCD_EN <= 0;
                        timer <= timer + 1;
                    end else if (timer >= 40) begin
                        state <= S_SEND_CHAR;
                        timer <= 0;
                        char_idx <= 16; // 從第 16 個字元繼續寫第二行
                    end else begin
                        timer <= timer + 1;
                    end
                end

                // ==========================================
                // 階段 5：休眠等待刷新 (約 125ms)
                // ==========================================
                S_WAIT_100K: begin
                    if (timer >= 100000) begin
                        state <= S_LINE1_CMD; // 時間到，回到設定第一行重新刷新
                        timer <= 0;
                    end else begin
                        timer <= timer + 1;
                    end
                end

                default: state <= S_INIT;
            endcase
        end
    end

endmodule

module lcd_rom_wrapper (
    input clk,
    input [2:0] state,
    input [17:0] SW,
    output [127:0] data
);

    localparam [2:0]
        S_I2C        = 0, // 上電先進行 I2C 初始化
        S_IDLE       = 1,
        S_RECD       = 2,
        S_RECD_PAUSE = 3,
        S_PLAY       = 4,
        S_PLAY_PAUSE = 5;

    wire [4:0] address;
    assign address[0] = (state == S_IDLE) || SW[5];
    assign address[1] = (state == S_RECD);
    assign address[2] = (state == S_RECD_PAUSE);
    assign address[3] = (state == S_PLAY);
    assign address[4] = (state == S_PLAY_PAUSE);

    lcd_rom X1 (
        address, clk, data
    );
    
endmodule