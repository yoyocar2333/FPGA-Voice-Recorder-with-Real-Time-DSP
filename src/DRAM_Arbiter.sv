module memory_adaptor (
    input              clk,
    input              reset_n,

    // writer
    input       [25:0] w_addr,
    input       [15:0] w_data,
    input              w_valid,

    // reader
    input              r_enable, // please do it 144 cycles early
    input       [25:0] r_addr,
    output wire [15:0] r_data,
    output wire        r_valid, // unused

    // SDRAM
    output reg  [24:0] m_address,
    output reg  [31:0] m_write_data,
    output reg         m_read,
    output reg         m_write,
    input  wire [31:0] m_read_data,
    input  wire        m_read_data_valid,
    input  wire        m_wait_request
);

    wire ma_write, ma_read;
    wire [24:0] ma_write_addr, ma_read_addr;
    wire [31:0] ma_write_data, ma_read_data;
    wire ma_wait_request, ma_read_data_valid;

    memory_arbiter X1 (
        .clk                (clk),
        .reset_n            (reset_n),

        .s_write            (ma_write),
        .s_read             (ma_read),
        .s_write_addr       (ma_write_addr),
        .s_read_addr        (ma_read_addr),
        .s_write_data       (ma_write_data),
        .s_read_data        (ma_read_data),
        .s_wait_request     (ma_wait_request),
        .s_read_data_valid  (ma_read_data_valid),

        .m_address          (m_address),
        .m_write_data       (m_write_data),
        .m_read             (m_read),
        .m_write            (m_write),
        .m_read_data        (m_read_data),
        .m_read_data_valid  (m_read_data_valid),
        .m_wait_request     (m_wait_request)
    );

    memory_compactor X2 (
        .clk            (clk),
        .reset_n        (reset_n),

        .addr           (w_addr),
        .data           (w_data),
        .in_valid       (w_valid),

        .wait_request   (ma_wait_request),
        .m_write        (ma_write),
        .m_addr         (ma_write_addr),
        .m_data         (ma_write_data)
    );

    wire [7:0] c_addr;
    wire [31:0] c_data;
    wire c_wen;
    wire [15:0] c_high, c_low;

    passionate_cache X3 (
        .clk    (clk),
        .reset_n(reset_n),

        .addr       (r_addr),
        .prefetch_en(r_enable),
        .init_done  (r_valid),

        .c_addr (c_addr),
        .c_data (c_data),
        .wren   (c_wen),

        .wait_request   (ma_wait_request),
        .m_read         (ma_read),
        .m_addr         (ma_read_addr),
        .m_data         (ma_read_data),
        .m_data_valid   (ma_read_data_valid)
    );

    bram_cache X4 (
        .clock      (clk),
        .data       (c_data),
        .rdaddress  (c_addr),
        .wren       (c_wen),
        .wraddress  (r_addr[8:1]),
        .q          ({c_high, c_low})
    );
    assign r_data = r_addr[0]? c_high: c_low;

endmodule

module memory_arbiter (
    input  wire        clk,
    input  wire        reset_n, // async

    // toward a master
    input  wire        s_write,
    input  wire        s_read,
    input  wire [24:0] s_write_addr,
    input  wire [24:0] s_read_addr,
    input  wire [31:0] s_write_data,
    output wire [31:0] s_read_data,
    output reg         s_wait_request,
    output wire        s_read_data_valid,

    // toward a slave (SDRAM Controller)
    output reg  [24:0] m_address,
    output reg  [31:0] m_write_data,
    output reg         m_read,
    output reg         m_write,
    input  wire [31:0] m_read_data,
    input  wire        m_read_data_valid,
    input  wire        m_wait_request
);

    assign s_read_data = m_read_data;
    assign s_read_data_valid = m_read_data_valid;

    localparam
        IDLE = 0,
        READ = 1,
        WRITE= 2;
    reg [1:0] state, next_state;

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (s_read) next_state = READ;
                else if (s_write) next_state = WRITE;
            end
            READ: begin
                if (~m_wait_request) next_state = IDLE;
            end
            WRITE: begin
                if (~m_wait_request) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    reg [24:0] stored_address, next_stored_address;
    reg [31:0] stored_write_data, next_stored_write_data;

    always_comb begin
        s_wait_request = 1'b0;
        m_address = stored_address;
        m_write_data = s_write_data;
        m_read = 1'b0;
        m_write= 1'b0;
        next_stored_address = stored_address;
        next_stored_write_data = stored_write_data;

        case (state)
            IDLE: begin
                if (s_read) begin
                    m_address = s_read_addr;
                    m_read = 1'b1;
                end
                else if (s_write) begin
                    m_address = s_write_addr;
                    m_write = 1'b1;
                end
                if (s_read || s_write) begin
                    s_wait_request = 1'b1;
                    next_stored_address = m_address;
                    next_stored_write_data = s_write_data;
                end
            end
            READ: begin
                s_wait_request = m_wait_request;
                m_read = 1'b1;
            end
            WRITE: begin
                s_wait_request = m_wait_request;
                m_write = 1'b1;
                m_write_data = stored_write_data;
            end
            default: begin
                
            end
        endcase
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            stored_address <= '0;
            stored_write_data <= '0;
        end else begin
            stored_address <= next_stored_address;
            stored_write_data <= next_stored_write_data;
        end
    end
    
endmodule

module memory_compactor (
    input clk,
    input reset_n, // async

    input [25:0] addr,
    input [15:0] data,
    input in_valid,

    input wait_request,
    output m_write,
    output [24:0] m_addr,
    output [31:0] m_data
);

    // State Encoding
    localparam IDLE   = 2'b00;
    localparam WAIT   = 2'b01;
    localparam WRITE  = 2'b10;
    // localparam DROP   = 2'b11;

    reg [1:0] state, next_state;
    
    reg [15:0] low_word,  next_low_word;
    reg [15:0] high_word, next_high_word;
    reg [24:0] addr_reg,  next_addr_reg;
    reg [9:0]  timer,     next_timer;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= IDLE;
            low_word  <= 16'd0;
            high_word <= 16'd0;
            addr_reg  <= 25'd0;
            timer     <= '0;
        end else begin
            state     <= next_state;
            low_word  <= next_low_word;
            high_word <= next_high_word;
            addr_reg  <= next_addr_reg;
            timer     <= next_timer;
        end
    end

    wire [9:0] timer_inc; wire timer_overflow;
    assign {timer_overflow, timer_inc} = timer + 6'b1;

    always @(*) begin
        next_state     = state;
        next_low_word  = low_word;
        next_high_word = high_word;
        next_addr_reg  = addr_reg;
        next_timer     = '0;

        case (state)
            IDLE: begin
                if (in_valid) begin
                    next_low_word = data;
                    next_addr_reg = addr[25:1];
                    next_state    = WAIT;
                end
            end

            WAIT: begin
                if (in_valid) begin
                    next_high_word = data;
                    next_state     = WRITE;
                end else if (timer_overflow) begin
                    next_state     = IDLE;
                end
                next_timer = timer_inc;
            end

            WRITE: begin
                if (!wait_request) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    assign m_write = (state == WRITE);
    assign m_addr  = addr_reg;
    assign m_data  = {high_word, low_word};
    
endmodule

module passionate_cache (
    input clk,
    input reset_n, // async

    // to master, no ack
    input [25:0] addr,
    input prefetch_en,
    output init_done,

    // to the actual cache
    output [7:0] c_addr,
    output [31:0] c_data,
    output wren,

    // to SDRAM controller
    input wait_request,
    output reg m_read,
    output [24:0] m_addr,
    input [31:0] m_data,
    input m_data_valid
);

    // --- State Encoding ---
    localparam S_IDLE         = 3'd0;
    localparam S_INIT_LOOP    = 3'd1;
    localparam S_MONITOR      = 3'd2;
    localparam S_FETCH_AHEAD  = 3'd3;
    localparam S_FETCH_BEHIND = 3'd4;

    reg [2:0] state, next_state;

    // --- Internal Registers ---
    reg [22:0] last_block_addr, next_last_block_addr; 
    reg signed [5:0] init_cnt, next_init_cnt;
    
    // --- Logic Signals ---
    reg start_fetch_pulse;
    reg [24:0] fetch_target;
    wire fetcher_busy, fetcher_done;
    wire [22:0] current_block_addr = addr[25:3];

    // --- Combinational Logic Block ---
    always @(*) begin
        // Defaults to avoid latches and keep state
        next_state           = state;
        next_last_block_addr = last_block_addr;
        next_init_cnt        = init_cnt;
        
        start_fetch_pulse    = 1'b0;
        fetch_target         = {current_block_addr, 2'b00};

        case (state)
            S_IDLE: begin
                if (prefetch_en) begin
                    next_last_block_addr = current_block_addr;
                    next_init_cnt        = -6'sd16;
                    next_state           = S_INIT_LOOP;
                end
            end

            S_INIT_LOOP: begin
                // Target is current center + the walking offset
                fetch_target = {current_block_addr, 2'b00} + {{19{init_cnt[5]}}, init_cnt};
                
                if (!fetcher_busy && !fetcher_done) begin
                    start_fetch_pulse = 1'b1;
                end

                if (fetcher_done) begin
                    if (init_cnt >= 6'sd16) begin
                        next_state = S_MONITOR;
                    end else begin
                        next_init_cnt = init_cnt + 6'sd4;
                        // Stay in S_INIT_LOOP
                    end
                end
            end

            S_MONITOR: begin
                if (!prefetch_en) begin
                    next_state = S_IDLE;
                end else
                if (current_block_addr > last_block_addr) begin
                    next_state = S_FETCH_AHEAD;
                end 
                else if (current_block_addr < last_block_addr) begin
                    next_state = S_FETCH_BEHIND;
                end
            end

            S_FETCH_AHEAD: begin
                // Fetch the leading edge of the +16 word window
                fetch_target = {current_block_addr, 2'b00} + 25'd16;
                if (!fetcher_busy && !fetcher_done) start_fetch_pulse = 1'b1;
                
                if (fetcher_done) begin
                    next_last_block_addr = current_block_addr;
                    next_state           = S_MONITOR;
                end
            end

            S_FETCH_BEHIND: begin
                // Fetch the trailing edge of the -16 word window
                fetch_target = {current_block_addr, 2'b00} - 25'd16;
                if (!fetcher_busy && !fetcher_done) start_fetch_pulse = 1'b1;
                
                if (fetcher_done) begin
                    next_last_block_addr = current_block_addr;
                    next_state           = S_MONITOR;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

    // --- Sequential Logic Block ---
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= S_IDLE;
            last_block_addr <= 23'b0;
            init_cnt        <= -6'sd16;
        end else begin
            state           <= next_state;
            last_block_addr <= next_last_block_addr;
            init_cnt        <= next_init_cnt;
        end
    end

    // --- Sub-module Instance ---
    block_fetcher fetcher_inst (
        .clk(clk),
        .reset_n(reset_n),
        .start_f(start_fetch_pulse),
        .start_addr(fetch_target),
        .busy(fetcher_busy),
        .done(fetcher_done),
        .c_addr(c_addr),
        .c_data(c_data),
        .wren(wren),
        .wait_request(wait_request),
        .m_read(m_read),
        .m_addr(m_addr),
        .m_data(m_data),
        .m_data_valid(m_data_valid)
    );

    assign init_done = (state==S_MONITOR) || (state==S_FETCH_AHEAD) || (state==S_FETCH_BEHIND);
    
endmodule

module block_fetcher (
    input  clk,
    input  reset_n,

    // Control from Top-Level
    input  start_f,
    input  [24:0] start_addr, 
    output reg busy,
    output reg done,

    // To Cache
    output [7:0]  c_addr,
    output [31:0] c_data,
    output reg    wren,

    // To SDRAM
    input         wait_request,
    output reg    m_read,
    output [24:0] m_addr,
    input  [31:0] m_data,
    input         m_data_valid
);

    // State Encoding
    localparam IDLE      = 2'd0;
    localparam SEND_REQ  = 2'd1;
    localparam WAIT_DATA = 2'd2;
    localparam COMPLETE  = 2'd3;

    reg [1:0]  state, next_state;
    reg [1:0]  word_cnt, next_word_cnt;
    wire [1:0] word_cnt_inc; wire word_cnt_overflow;
    assign {word_cnt_overflow, word_cnt_inc} = word_cnt + 2'b1;
    reg [24:0] base_addr_reg, next_base_addr_reg;

    // --- Combinational Block ---
    always @(*) begin
        // Default values to avoid latches
        next_state         = state;
        next_word_cnt      = word_cnt;
        next_base_addr_reg = base_addr_reg;
        
        m_read = 1'b0;
        wren   = 1'b0;
        busy   = 1'b1;
        done   = 1'b0;

        case (state)
            IDLE: begin
                busy = 1'b0;
                if (start_f) begin
                    next_base_addr_reg = {start_addr[24:2], 2'b0};
                    next_word_cnt      = 2'b0;
                    next_state         = SEND_REQ;
                end
            end

            SEND_REQ: begin
                m_read = 1'b1;
                if (!wait_request) begin
                    if (m_data_valid) begin
                        wren = 1'b1;
                        next_word_cnt = word_cnt_inc;
                        if (word_cnt_overflow) begin
                            next_state = COMPLETE;
                        end
                    end else begin
                        next_state = WAIT_DATA;
                    end
                end
            end

            WAIT_DATA: begin
                if (m_data_valid) begin
                    wren = 1'b1;
                    next_word_cnt = word_cnt_inc;
                    if (word_cnt_overflow) begin
                        next_state = COMPLETE;
                    end else begin
                        next_state = SEND_REQ;
                    end
                end
            end

            COMPLETE: begin
                done       = 1'b1;
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // --- Sequential Block ---
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= IDLE;
            word_cnt      <= 2'b0;
            base_addr_reg <= 25'b0;
        end else begin
            state         <= next_state;
            word_cnt      <= next_word_cnt;
            base_addr_reg <= next_base_addr_reg;
        end
    end

    // --- Data Path ---
    assign m_addr = base_addr_reg + word_cnt;
    assign c_addr = m_addr[7:0]; 
    assign c_data = m_data;

endmodule
