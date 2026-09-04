`default_nettype none

module hz_predictor_roms (
    input  wire [5:0] Block,
    input  wire [7:0] Square_A_Address,
    input  wire [4:0] Square_B_Address,
    input  wire [7:0] Cube_Address,
    output wire [52:0] C0,
    output wire [42:0] C1,
    output wire [32:0] C2,
    output wire [22:0] C3,
    output wire [12:0] C4,
    output wire [2:0] C5,
    output wire [15:0] Square_A,
    output wire [9:0] Square_B,
    output wire [23:0] Cube
);
    reg [166:0] Coeff_Mem [0:63];
    reg [15:0] Square_A_Mem [0:255];
    reg [9:0] Square_B_Mem [0:31];
    reg [23:0] Cube_Mem [0:255];

    initial begin
        $readmemh("build/coeff_rom.mem", Coeff_Mem);
        $readmemh("build/square_a.mem", Square_A_Mem);
        $readmemh("build/square_b.mem", Square_B_Mem);
        $readmemh("build/cube.mem", Cube_Mem);
    end

    wire [166:0] Coeff = Coeff_Mem[Block];
    assign C0 = {1'b1, Coeff[166:115]};
    assign C1 = Coeff[114:72];
    assign C2 = Coeff[71:39];
    assign C3 = Coeff[38:16];
    assign C4 = Coeff[15:3];
    assign C5 = Coeff[2:0];
    assign Square_A = Square_A_Mem[Square_A_Address];
    assign Square_B = Square_B_Mem[Square_B_Address];
    assign Cube = Cube_Mem[Cube_Address];
endmodule

`default_nettype wire
