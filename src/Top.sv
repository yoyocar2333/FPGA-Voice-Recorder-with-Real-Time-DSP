`default_nettype none
module Top (
	input i_rst_n,
	input i_clk,   // 12 MHz
	input i_key_0,
	input i_key_1,
	input i_key_2,
	input [3:0] i_speed, // design how user can decide mode on your own
    input i_slowmode, // 0 means constant interpolation, 1 means linear interpolation
    input [17:0] SW,
	
	// AudDSP and SRAM
	output [19:0] o_SRAM_ADDR,
	inout  [15:0] io_SRAM_DQ,
	output        o_SRAM_WE_N,
	output        o_SRAM_CE_N,
	output        o_SRAM_OE_N,
	output        o_SRAM_LB_N,
	output        o_SRAM_UB_N,
	
	// I2C
	input  i_clk_100k,
	output o_I2C_SCLK,
	inout  io_I2C_SDAT,
	
	// AudPlayer
	input  i_AUD_ADCDAT,
	inout  i_AUD_ADCLRCK,
	inout  i_AUD_BCLK,
	inout  i_AUD_DACLRCK,
	output o_AUD_DACDAT,

	// SEVENDECODER (optional display)
	// output [5:0] o_record_time,
	output [10:0] o_play_time,
    output [3:0] actual_speed,
    output is_slow,
    output [2:0] mode,

	// LCD (optional display)
	input        i_clk_800k,
	inout  [7:0] o_LCD_DATA,
	output       o_LCD_EN,
	output       o_LCD_RS,
	output       o_LCD_RW,
	output       o_LCD_ON,
	output       o_LCD_BLON,

	// LED
	// output  [8:0] o_ledg,
	// output [17:0] o_ledr,

    // DRAM
    input  i_DRAM_waitrequest,
    output [24:0] o_DRAM_address,
    output o_DRAM_write,
    output o_DRAM_read,
    output [31:0] o_DRAM_writedata,
    input  [31:0] i_DRAM_readdata,
    input  i_DRAM_readdatavalid
);

    // ==========================================
    // 2. 狀態機定義 (FSM)
    // ==========================================
    localparam [2:0]
        S_I2C        = 0, // 上電先進行 I2C 初始化
        S_IDLE       = 1,
        S_RECD       = 2,
        S_RECD_PAUSE = 3,
        S_PLAY       = 4,
        S_PLAY_PAUSE = 5;

    logic [2:0] state_r, state_w;
    assign mode = state_r;

    // 按鍵邊緣偵測 (避免按住不放導致狀態狂跳)
    logic key0_edge, key1_edge, key2_edge;
    assign key0_edge = i_key_0;
    assign key1_edge = i_key_1;
    assign key2_edge = i_key_2;

    // ==========================================
    // 3. I2C Initialization
    // ==========================================
    logic i2c_oen, i2c_sdat;
    logic i2c_finished;
    logic i2c_start_r, i2c_start_w;

    assign io_I2C_SDAT = (i2c_oen) ? i2c_sdat : 1'bz;

    assign i2c_start_w = 1'b0;
    always_ff @(posedge i_clk_100k or negedge i_rst_n) begin
        if (~i_rst_n) begin
            i2c_start_r <= 1'b1;
        end else begin
            i2c_start_r <= i2c_start_w;
        end
    end

    I2cInitializer init0(
        .i_rst_n(i_rst_n),
        .i_clk(i_clk_100k),
        .i_start(1'b1),
        .o_finished(i2c_finished),
        .o_sclk(o_I2C_SCLK),
        .o_sdat(i2c_sdat),
        .o_oen(i2c_oen) 
    );

    // ==========================================
    // 4. SRAM Control Logic
    // ==========================================
    logic [25:0] addr_record, addr_play;
    logic [15:0] data_record, data_play, dram_read_data;
    logic recorder_data_valid;
    wire [25:0] long_play_time = (state_r == S_RECD || state_r == S_RECD_PAUSE)? addr_record: addr_play;
    assign o_play_time = long_play_time[25:15];

    assign o_SRAM_CE_N = 1'b0;
    assign o_SRAM_OE_N = 1'b0;
    assign o_SRAM_LB_N = 1'b0;
    assign o_SRAM_UB_N = 1'b0;

    // 只有在錄音狀態時，WE_N 才為 0 (寫入)，其餘為讀取
    assign o_SRAM_WE_N = (state_r == S_RECD) ? 1'b0 : 1'b1;
    
    // 位址與資料的多工器
    wire [25:0] temp_addr = (state_r == S_RECD || state_r == S_RECD_PAUSE) ? addr_record : addr_play;
    
    // 修正 1：SRAM 的位址寬度是 20-bit，不是 16-bit
    assign o_SRAM_ADDR = temp_addr[19:0]; 
    
    assign io_SRAM_DQ  = (state_r == S_RECD) ? data_record : 16'dz; // 錄音時輸出資料給SRAM
    assign data_play   = (state_r != S_RECD) ? io_SRAM_DQ  : 16'd0; // 播放時從SRAM讀資料
    
    // 修正 2：使用 SW[16] 來動態切換播放時要讀取 SRAM 還是 DRAM
    // SW[16] = 0 -> 聽 SRAM 的聲音
    // SW[16] = 1 -> 聽 DRAM 的聲音
    wire [15:0] active_memory_data = SW[16] ? dram_read_data : data_play;
    wire [15:0] data_play_2 = (state_r != S_RECD) ? active_memory_data : data_record;
    logic [15:0] audio_rom_q;

    // ==========================================
    // 5. Audio Sub-modules (DSP, Player, Recorder)
    // ==========================================
    logic [15:0] dac_data;

    logic [3:0] c_speed; assign actual_speed = c_speed;
    logic c_fast, c_slow_0, c_slow_1;
    speed_translator XX48(
        .i_speed(i_speed),
        .i_slowmode(i_slowmode),
        .o_speed(c_speed),
        .o_fast(c_fast),
        .o_slow(is_slow),
        .o_slow_0(c_slow_0),
        .o_slow_1(c_slow_1)
    );
    
    AudDSP dsp0(
        .i_rst_n(i_rst_n),
        .i_clk(i_AUD_BCLK),
        .i_start(state_r == S_PLAY),
        .i_pause(state_r == S_PLAY_PAUSE),
        .i_stop(state_r == S_IDLE),
        .i_speed(c_speed),          // 將 SW 傳入控制倍速
	    .i_fast(c_fast),            // if 1 then fast, 0 then slow
	    .i_slow_0(c_slow_0),        // constant interpolation
	    .i_slow_1(c_slow_1),        // linear interpolation
        .i_reverse(SW[5]),
        .i_daclrck(i_AUD_DACLRCK),
        // .i_sram_data(data_play),
        .i_sram_data(SW[17]? audio_rom_q: data_play_2),
        .o_dac_data(dac_data),
        .o_sram_addr(addr_play)
    );

    AudPlayer player0(
        .i_rst_n(i_rst_n),
        .i_bclk(i_AUD_BCLK),
        .i_daclrck(i_AUD_DACLRCK),
        .i_en(state_r == S_PLAY), // 只有播放時啟用
        .i_dac_data(dac_data),
        .o_aud_dacdat(o_AUD_DACDAT)
    );

	// AudPlayer player0(
    //     .i_rst_n(i_rst_n),
    //     .i_bclk(i_AUD_BCLK),
    //     .i_daclrck(i_AUD_DACLRCK),
    //     .i_en(1'b1),                     // 【測試修改】永遠啟用播放
    //     .i_dac_data(data_record),        // 【測試修改】直接把 Recorder 錄到的資料丟給 Player
    //     .o_aud_dacdat(o_AUD_DACDAT)
    // );

    AudRecorder recorder0(
        .i_rst_n(i_rst_n), 
        .i_clk(i_AUD_BCLK),
        .i_lrc(i_AUD_ADCLRCK),
        .i_start(state_r == S_RECD),
        .i_pause(state_r == S_RECD_PAUSE),
        .i_stop(state_r == S_IDLE),
        .i_data(i_AUD_ADCDAT),
        .o_address(addr_record),
        .o_data(data_record),
        .o_data_valid(recorder_data_valid)
    );

    memory_adaptor XX6 (
        .clk(i_AUD_BCLK),
        .reset_n(i_rst_n),

        .w_addr(addr_record),
        .w_data(data_record),
        .w_valid(recorder_data_valid),

        .r_enable(state_r == S_IDLE || state_r == S_PLAY || state_r == S_PLAY_PAUSE),
        .r_addr(addr_play),
        .r_data(dram_read_data),
        .r_valid(),

        .m_address(o_DRAM_address),
        .m_write_data(o_DRAM_writedata),
        .m_read(o_DRAM_read),
        .m_write(o_DRAM_write),
        .m_read_data(i_DRAM_readdata),
        .m_read_data_valid(i_DRAM_readdatavalid),
        .m_wait_request(i_DRAM_waitrequest)
    );

    audio_rom_wrapper XX16 (
        .address(addr_play),
        .clock(i_AUD_BCLK),
        .q(audio_rom_q)
    );

    lcd_controller XX8 (
        .clk_800k(i_clk_800k),
        .reset_n(i_rst_n),
        .SW(SW),
        .ext_state(state_r),
        .speed(c_speed),
        .LCD_ON(o_LCD_ON),
        .LCD_BLON(o_LCD_BLON),
        .LCD_RW(o_LCD_RW),
        .LCD_EN(o_LCD_EN),
        .LCD_RS(o_LCD_RS),
        .LCD_DATA(o_LCD_DATA)
    );

    // ==========================================
    // 6. Main FSM Logic (主狀態機)
    // ==========================================
    always_comb begin
        state_w = state_r;
        case (state_r)
            S_I2C: begin
                if (i2c_finished) state_w = S_IDLE;
            end
            S_IDLE: begin
                if (key0_edge) state_w = S_RECD;
                else if (key1_edge) state_w = S_PLAY;
            end
            S_RECD: begin
                if (key2_edge) state_w = S_IDLE;          // Stop
                else if (key0_edge) state_w = S_RECD_PAUSE; // Pause
            end
            S_RECD_PAUSE: begin
                if (key2_edge) state_w = S_IDLE;          // Stop
                else if (key0_edge) state_w = S_RECD;       // Resume
            end
            S_PLAY: begin
                if (key2_edge) state_w = S_IDLE;          // Stop
                else if (key1_edge) state_w = S_PLAY_PAUSE; // Pause
                // 你也可以在這裡加入條件：當 addr_play 讀到盡頭時自動回到 S_IDLE
            end
            S_PLAY_PAUSE: begin
                if (key2_edge) state_w = S_IDLE;          // Stop
                else if (key1_edge) state_w = S_PLAY;       // Resume
            end
            default: state_w = S_I2C;
        endcase
    end

    always_ff @(posedge i_AUD_BCLK or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_r <= S_I2C;
        end else begin
            state_r <= state_w;
        end
    end

    // ==========================================
    // 7. Bonus: 狀態指示燈 (七段顯示器)
    // ==========================================
    // 簡單的 Decoder：將目前狀態顯示在七段顯示器上 (0:I2C, 1:IDLE, 2:RECD, 3:RPAS, 4:PLAY, 5:PPAS)
    /* logic [6:0] hex_table [0:15];
    assign hex_table[0] = 7'b1000000; // '0'
    assign hex_table[1] = 7'b1111001; // '1'
    // ... 自行補齊七段顯示器查表 ...
    assign o_hex0 = hex_table[state_r];
    assign o_hex1 = 7'b1111111; // 關閉
    */

endmodule