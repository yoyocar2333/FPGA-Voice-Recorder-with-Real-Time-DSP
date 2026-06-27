module AudPlayer (
    input  logic        i_rst_n,
    input  logic        i_bclk,      // AUD_BCLK
    input  logic        i_daclrck,   // AUD_DACLRCK
    input  logic        i_en,        // 播放啟用訊號
    input  logic [15:0] i_dac_data,  // 來自 DSP 或 Recorder 的 16-bit 資料
    output logic        o_aud_dacdat // AUD_DACDAT
);

    // 為了精準對齊，我們在 posedge 偵測 LRCK 邊緣
    logic lrc_delay;
    logic lrc_fall;
    always_ff @(posedge i_bclk or negedge i_rst_n) begin
        if (!i_rst_n) lrc_delay <= 1'b0;
        else          lrc_delay <= i_daclrck;
    end
    assign lrc_fall = (lrc_delay == 1'b1 && i_daclrck == 1'b0);

    logic [4:0]  bit_cnt,        bit_cnt_next;
    logic [15:0] shift_reg,      shift_reg_next;
    logic        transmitting,   transmitting_next;
    logic        o_aud_dacdat_next;

    always_comb begin
        // Default assignments: Keep current state unless conditions are met
        bit_cnt_next      = bit_cnt;
        shift_reg_next    = shift_reg;
        transmitting_next = transmitting;
        o_aud_dacdat_next = o_aud_dacdat;

        if (lrc_fall) begin
            // Start of frame
            transmitting_next = 1'b1;
            bit_cnt_next      = 5'd15;
            
            if (i_en) begin
                shift_reg_next    = i_dac_data;   // Load new data
                o_aud_dacdat_next = i_dac_data[15]; // Drive MSB immediately
            end else begin
                shift_reg_next    = 16'd0;
                o_aud_dacdat_next = 1'b0;         // Mute if not enabled
            end
        end else if (transmitting) begin
            if (bit_cnt == 5'd0) begin
                // End of transmission
                transmitting_next = 1'b0;
                o_aud_dacdat_next = 1'b0;
            end else begin
                // Decrement counter and drive next bit
                bit_cnt_next      = bit_cnt - 5'd1;
                o_aud_dacdat_next = shift_reg[bit_cnt - 1];
            end
        end
    end

    always_ff @(posedge i_bclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            transmitting <= 1'b0;
            o_aud_dacdat <= 1'b0;
            bit_cnt      <= 5'd15;
            shift_reg    <= 16'd0;
        end else begin
            transmitting <= transmitting_next;
            o_aud_dacdat <= o_aud_dacdat_next;
            bit_cnt      <= bit_cnt_next;
            shift_reg    <= shift_reg_next;
        end
    end
endmodule