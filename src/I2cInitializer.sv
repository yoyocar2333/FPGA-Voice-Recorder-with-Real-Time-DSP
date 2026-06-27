module I2cInitializer (
    input  logic i_rst_n,
    input  logic i_clk,      // 輸入 100kHz Clock
    input  logic i_start,    // 初始化觸發訊號
    output logic o_finished, // 初始化完成訊號
    output logic o_sclk,     // I2C 串列時脈 (50kHz)
    output logic o_sdat,     // I2C 串列資料
    output logic o_oen       // I2C Output Enable (1: 寫入 SDA, 0: 讀取 Ack)
);

    // 根據講義 p.12 提供的 7 筆 24-bit 初始值
    logic [23:0] rom [0:6];
    assign rom[0] = 24'b0011_0100_000_1111_0_0000_0000; // Reset
    assign rom[1] = 24'b0011_0100_000_0100_0_0001_0101; // Analogue Audio Path
    assign rom[2] = 24'b0011_0100_000_0101_0_0000_0000; // Digital Audio Path
    assign rom[3] = 24'b0011_0100_000_0110_0_0000_0000; // Power Down Control
    assign rom[4] = 24'b0011_0100_000_0111_0_0100_0010; // Digital Audio Interface Format
    assign rom[5] = 24'b0011_0100_000_1000_0_0001_1001; // Sampling Control
    assign rom[6] = 24'b0011_0100_000_1001_0_0000_0001; // Active Control

    // 狀態機定義
    typedef enum logic [3:0] {
        S_IDLE, 
        S_START, 
        S_DAT_LOW, S_DAT_HIGH, 
        S_ACK_LOW, S_ACK_HIGH,
        S_STOP_LOW, S_STOP_HIGH, S_STOP_END, 
        S_DONE
    } state_t;

    state_t state_r, state_w;
    logic [2:0] word_cnt_r, word_cnt_w; // 紀錄傳到第幾個暫存器 (0~6)
    logic [4:0] bit_cnt_r, bit_cnt_w;   // 紀錄 24-bit 傳到哪 (24 down to 0)

    // 輸出控制邏輯
    always_comb begin
        o_sclk = 1'b1;
        o_sdat = 1'b1;
        o_oen  = 1'b1;
        o_finished = 1'b0;

        case(state_r)
            S_IDLE: begin
                o_sclk = 1'b1; o_sdat = 1'b1; o_oen = 1'b1;
            end
            S_START: begin
                o_sclk = 1'b1; o_sdat = 1'b0; o_oen = 1'b1; // SCL=1時拉低SDA產生Start
            end
            S_DAT_LOW: begin
                o_sclk = 1'b0; o_sdat = rom[word_cnt_r][bit_cnt_r - 1]; o_oen = 1'b1;
            end
            S_DAT_HIGH: begin
                o_sclk = 1'b1; o_sdat = rom[word_cnt_r][bit_cnt_r - 1]; o_oen = 1'b1;
            end
            S_ACK_LOW: begin
                o_sclk = 1'b0; o_sdat = 1'b0; o_oen = 1'b0; // 釋放 SDA 讓 Slave 回傳 Ack
            end
            S_ACK_HIGH: begin
                o_sclk = 1'b1; o_sdat = 1'b0; o_oen = 1'b0; 
            end
            S_STOP_LOW: begin
                o_sclk = 1'b0; o_sdat = 1'b0; o_oen = 1'b1;
            end
            S_STOP_HIGH: begin
                o_sclk = 1'b1; o_sdat = 1'b0; o_oen = 1'b1;
            end
            S_STOP_END: begin
                o_sclk = 1'b1; o_sdat = 1'b1; o_oen = 1'b1; // SCL=1時拉高SDA產生Stop
            end
            S_DONE: begin
                o_sclk = 1'b1; o_sdat = 1'b1; o_oen = 1'b1; o_finished = 1'b1;
            end
        endcase
    end

    // 狀態轉移邏輯
    always_comb begin
        state_w = state_r;
        word_cnt_w = word_cnt_r;
        bit_cnt_w = bit_cnt_r;

        case(state_r)
            S_IDLE: begin
                if(i_start) state_w = S_START;
            end
            S_START: begin
                state_w = S_DAT_LOW;
            end
            S_DAT_LOW: begin
                state_w = S_DAT_HIGH;
            end
            S_DAT_HIGH: begin
                bit_cnt_w = bit_cnt_r - 1;
                // 每傳送 8 bits，進入 Ack 狀態
                if (bit_cnt_r - 1 == 16 || bit_cnt_r - 1 == 8 || bit_cnt_r - 1 == 0)
                    state_w = S_ACK_LOW;
                else
                    state_w = S_DAT_LOW;
            end
            S_ACK_LOW: begin
                state_w = S_ACK_HIGH;
            end
            S_ACK_HIGH: begin
                if (bit_cnt_r == 0) // 24 bits 全傳完
                    state_w = S_STOP_LOW;
                else
                    state_w = S_DAT_LOW;
            end
            S_STOP_LOW: begin
                state_w = S_STOP_HIGH;
            end
            S_STOP_HIGH: begin
                state_w = S_STOP_END;
            end
            S_STOP_END: begin
                if (word_cnt_r >= 6) begin // 7 個指令全送完
                    state_w = S_DONE;
                end else begin
                    word_cnt_w = word_cnt_r + 1; // 準備送下一個指令
                    bit_cnt_w = 24;
                    state_w = S_START;
                end
            end
            S_DONE: begin
                state_w = S_DONE;
            end
        endcase
    end

    // Sequential 邏輯
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            state_r <= S_IDLE;
            word_cnt_r <= 0;
            bit_cnt_r <= 24;
        end else begin
            state_r <= state_w;
            word_cnt_r <= word_cnt_w;
            bit_cnt_r <= bit_cnt_w;
        end
    end
endmodule