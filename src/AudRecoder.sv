module AudRecorder (
    input  logic        i_rst_n, 
    input  logic        i_clk,    // AUD_BCLK
    input  logic        i_lrc,    // AUD_ADCLRCK
    input  logic        i_start,  // 對應 Top.sv 錄音狀態
    input  logic        i_pause,  // 對應 Top.sv 暫停狀態
    input  logic        i_stop,   // 對應 Top.sv 停止狀態
    input  logic        i_data,   // AUD_ADCDAT
    output logic [25:0] o_address,
    output logic [15:0] o_data,
    output logic        o_data_valid
);

    // 偵測 LRCK 的下降沿 (左聲道起始)
    logic lrc_delay;
    logic lrc_fall;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) lrc_delay <= 1'b0;
        else          lrc_delay <= i_lrc;
    end
    // 當上一拍是 1，這一拍是 0，代表進入左聲道的 Empty Cycle
    assign lrc_fall = (lrc_delay == 1'b1 && i_lrc == 1'b0);

    logic [4:0]  bit_cnt,     bit_cnt_next;
    logic [15:0] shift_reg,   shift_reg_next;
    logic        receiving,   receiving_next;
    logic [25:0] o_address_next;
    logic [15:0] o_data_next;
    logic        o_data_valid_next;

    always_comb begin
        // Default assignments to avoid latches
        bit_cnt_next     = bit_cnt;
        receiving_next   = receiving;
        o_address_next   = o_address;
        o_data_next      = o_data;
        o_data_valid_next= 1'b0;
        shift_reg_next   = shift_reg;

        if (i_stop) begin
            o_address_next = 26'd0;
            receiving_next = 1'b0;
        end else if (lrc_fall) begin
            receiving_next = 1'b1;
            bit_cnt_next   = 5'd15;
        end else if (receiving) begin
            // Update shift register logic
            shift_reg_next[bit_cnt] = i_data;
            
            if (bit_cnt == 5'd0) begin
                receiving_next = 1'b0;
                o_data_next    = {shift_reg[15:1], i_data};
                
                if (i_start && !i_pause) begin
                    o_address_next = o_address + 26'd1;
                    o_data_valid_next = 1'b1;
                end
            end else begin
                bit_cnt_next = bit_cnt - 5'd1;
            end
        end
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            bit_cnt   <= 5'd0;
            receiving <= 1'b0;
            o_data    <= 16'd0;
            o_address <= 26'd0;
            shift_reg <= 16'd0;
            o_data_valid <= 1'b0;
        end else begin
            bit_cnt   <= bit_cnt_next;
            receiving <= receiving_next;
            o_data    <= o_data_next;
            o_address <= o_address_next;
            shift_reg <= shift_reg_next;
            o_data_valid <= o_data_valid_next;
        end
    end

endmodule