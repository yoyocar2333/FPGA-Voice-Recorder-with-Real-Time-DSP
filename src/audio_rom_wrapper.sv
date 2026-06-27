module audio_rom_wrapper (
    input [19:0] address,
    input clock,
    output [15:0] q
);

    wire [18:0] eff_addr = address[18:0];
    wire [7:0] q_rom;
    assign q = {q_rom, 8'b0};

    audio_rom X1 (
        .address(eff_addr),
        .clock(clock),
        .q(q_rom)
    );
    
endmodule