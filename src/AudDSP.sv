/* Feature:
i_speed represents speed from 2~8 and 0.5~0.125 and 1
[TODO] Please design the i_speed to use gray code. And output o_speed in radix-2 number.
*/
module speed_translator (
    input [3:0] i_speed,
    input i_slowmode,
    output [3:0] o_speed,
    output o_fast,
    output o_slow,
    output o_slow_0,
    output o_slow_1
);
    wire [3:0] bin_speed;   
    assign bin_speed[3] = i_speed[3];
    assign bin_speed[2] = i_speed[2];
    assign bin_speed[1] = bin_speed[2] ^ i_speed[1];
    assign bin_speed[0] = bin_speed[1] ^ i_speed[0];

    wire [2:0] init_speed = bin_speed[2:0];
    assign o_speed = init_speed + 3'b1;
    wire non_unity = | init_speed;
    assign o_fast =  bin_speed[3] && non_unity;
    assign o_slow = ~bin_speed[3] && non_unity;
    assign o_slow_0 = o_slow && ~i_slowmode;
    assign o_slow_1 = o_slow &&  i_slowmode;
    
endmodule

module AudDSP (
    input  logic        i_rst_n,
    input  logic        i_clk,       // 連接 i_AUD_BCLK (12MHz)
    input  logic        i_start,     // 播放中
    input  logic        i_pause,     // 暫停播放
    input  logic        i_stop,      // 停止 (重置位址)
    input  logic [3:0]  i_speed,     // 速度參數 N (從 SW 傳入)
    input  logic        i_fast,      // 快速播放模式
    input  logic        i_slow_0,    // 慢速：零次內插 (Piecewise-constant)
    input  logic        i_slow_1,    // 慢速：一次內插 (Linear interpolation)
    input  logic        i_reverse,
    input  logic        i_daclrck,   // 連接 i_AUD_DACLRCK (32kHz)
    input  logic [15:0] i_sram_data, // 來自 SRAM 的資料
    output logic [15:0] o_dac_data,  // 處理完畢，丟給 AudPlayer 的資料
    output logic [25:0] o_sram_addr  // 送給 SRAM 的讀取位址
);

    // logic r_reverse;
    // synchronizer X1 (i_clk, i_reverse, r_reverse);

    // ==========================================
    // 1. LRCK 邊緣偵測 (判斷何時需要處理下一個取樣點)
    // ==========================================
    logic lrc_delay;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) lrc_delay <= 1'b0;
        else          lrc_delay <= i_daclrck;
    end
    // 每當 LRCK 從 1 降到 0 (進入左聲道)，我們就更新一次音訊資料
    wire lrc_fall = (lrc_delay == 1'b1 && i_daclrck == 1'b0);

    // 速度保護：確保 N 至少為 1
    logic signed [3:0] N;
    assign N = (i_speed == 0) ? 4'd1 : i_speed;

    // ==========================================
    // 2. FSM 狀態機與內部暫存器
    // ==========================================
    // 為了安全讀取 SRAM 的 Y0 與 Y1，我們利用 LRCK (32kHz) 之間廣大的時間差 (375 個 BCLK) 來分步抓取
    typedef enum logic [2:0] {
        ST_IDLE,       // 等待 lrc_fall
        ST_FETCH_Y0,   // 送出位址讀取 Y0
        ST_LATCH_Y0,   // 鎖存 Y0
        ST_FETCH_Y1,   // 送出位址讀取 Y1 (為了內插準備)
        ST_LATCH_Y1,   // 鎖存 Y1
        ST_CALC        // 計算最終要輸出的聲音點
    } dsp_state_t;

    dsp_state_t state_r, state_w;
    
    logic [25:0] play_addr_r, play_addr_w;
    logic [3:0]  step_r, step_w; // 紀錄目前慢速播放走到第幾個內插點 (0 ~ N-1)
    logic [15:0] y0_r, y0_w;     // 當前資料點
    logic [15:0] y1_r, y1_w;     // 下一資料點
    logic [15:0] dac_data_w;

    // ==========================================
    // 3. DSP 運算核心 (Signed 運算避免爆音)
    // ==========================================
    logic signed [15:0] s_Y0, s_Y1;
    logic signed [16:0] diff;       // 差異可能超過 16-bit 範圍，需要 17-bit
    logic signed [21:0] mult;       // diff * step 乘積
    logic signed [15:0] step_diff;  // (Y1 - Y0) * i / N 的結果

    assign s_Y0 = signed'(y0_r);
    assign s_Y1 = signed'(y1_r);
    assign diff = s_Y1 - s_Y0;
    
    // step_r 本身是無號數，前綴 1'b0 轉為正的 signed 數來乘
    assign mult = diff * signed'({1'b0, step_r});

    always_comb begin
        // 合成器會將這段轉化為有效率的常數除法電路或位移器
        case(N)
            4'd1: step_diff = mult;
            4'd2: step_diff = mult >>> 1;
            4'd3: step_diff = mult / 3;
            4'd4: step_diff = mult >>> 2;
            4'd5: step_diff = mult / 5;
            4'd6: step_diff = mult / 6;
            4'd7: step_diff = mult / 7;
            4'd8: step_diff = mult >>> 3;
            default: step_diff = mult;
        endcase
    end

    logic signed [15:0] interp_val;
    assign interp_val = s_Y0 + step_diff; // 一次內插最終結果

    // ==========================================
    // 4. 狀態與指標控制
    // ==========================================
    always_comb begin
        state_w     = state_r;
        play_addr_w = play_addr_r;
        step_w      = step_r;
        y0_w        = y0_r;
        y1_w        = y1_r;
        dac_data_w  = o_dac_data;

        case (state_r)
            ST_IDLE: begin
                if (i_stop) begin
                    play_addr_w = 26'd0;
                    step_w      = 4'd0;
                    // dac_data_w  = 16'd0;
                end
                else if (lrc_fall) begin
                    if (i_start && !i_pause) begin
                        // 決定 Address 和 Step 如何前進
                        if (step_r + 1 >= N || i_fast) begin
                            play_addr_w = i_reverse? (play_addr_r + ((i_fast)? -N: -26'sd1)): (play_addr_r + ((i_fast)? N: 26'sd1));
                            step_w      = 4'd0;
                        end else begin
                            step_w      = step_r + 4'd1; // 繼續內插
                        end
                        state_w = ST_FETCH_Y0; // 開始去 SRAM 抓資料
                    end else begin
                        // dac_data_w = 16'd0; // 暫停時輸出靜音
                    end
                end
            end

            ST_FETCH_Y0: state_w = ST_LATCH_Y0;
            ST_LATCH_Y0: begin
                y0_w = i_sram_data;
                state_w = ST_FETCH_Y1;
            end
            ST_FETCH_Y1: state_w = ST_LATCH_Y1;
            ST_LATCH_Y1: begin
                y1_w = i_sram_data;
                state_w = ST_CALC;
            end
            ST_CALC: begin
                // 根據模式決定最終丟給 Player 的資料
                if (i_slow_1) begin
                    dac_data_w = unsigned'(interp_val); // 一次內插
                end else begin
                    dac_data_w = y0_r; // 正常模式
                end
                state_w = ST_IDLE;
            end
            default: state_w = ST_IDLE;
        endcase
    end

    // Sequential 邏輯
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_r     <= ST_IDLE;
            play_addr_r <= 26'd0;
            step_r      <= 4'd0;
            y0_r        <= 16'd0;
            y1_r        <= 16'd0;
            o_dac_data  <= 16'd0;
        end else begin
            state_r     <= state_w;
            play_addr_r <= play_addr_w;
            step_r      <= step_w;
            y0_r        <= y0_w;
            y1_r        <= y1_w;
            o_dac_data  <= dac_data_w;
        end
    end

    // 負責切換 SRAM 的位址 (非同步讀取)
    always_comb begin
        if (state_r == ST_FETCH_Y0 || state_r == ST_LATCH_Y0)
            o_sram_addr = play_addr_r;
        else
            o_sram_addr = i_reverse? (play_addr_r-26'd1): (play_addr_r+26'd1); // 為了抓取 Y1
    end

endmodule