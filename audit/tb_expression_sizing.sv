`timescale 1ns/1ps
`default_nettype none

// Audit-only IEEE 1800 expression-sizing probes. These deliberately mirror
// critical production idioms while keeping the production RTL byte-identical.
module tb_expression_sizing;
    reg [63:0] U64_A;
    reg [63:0] U64_B;
    reg [31:0] U32;
    wire [95:0] Product_64x32 = U64_A * U32;
    wire [127:0] Product_64x64 = U64_A * U64_B;

    reg signed [43:0] S44;
    reg signed [30:0] S31;
    wire signed [74:0] Product_S44xS31 = S44 * S31;

    reg signed [63:0] S64_A;
    reg signed [63:0] S64_B;
    wire signed [63:0] Chained_Signed = 3 * S64_A * S64_B;

    reg [79:0] Unsigned_Packed;
    wire signed [30:0] Signed_Slice = Unsigned_Packed[30:0];

    reg Carry_Low;
    wire signed [3:0] Candidate_M [0:4];
    genvar k;
    generate
        for (k = 0; k < 5; k = k + 1) begin : g_candidate_m
            assign Candidate_M[k] = Carry_Low ? k : k - 1;
        end
    endgenerate

    reg signed [99:0] Shift_Base;
    integer Shift_Amount;
    wire signed [99:0] Signed_Shift = Shift_Base <<< Shift_Amount;
    wire signed [99:0] Negated_Signed_Shift = -(Shift_Base <<< Shift_Amount);

    reg [32:0] RH33;
    reg [32:0] VH33;
    reg [63:0] Divisor;
    reg [31:0] Low;
    reg [63:0] Reciprocal_Remainder;
    reg [63:0] Dividend_Hi;
    reg [31:0] G;
    wire [65:0] G_Product = RH33 * VH33;
    wire [95:0] DL = Divisor * Low;
    wire [127:0] RX = Reciprocal_Remainder * Dividend_Hi;
    wire [95:0] GD = G * Divisor;

    integer Index;

    task automatic require;
        input Condition;
        input [8*96-1:0] Message;
        begin
            if (Condition !== 1'b1)
                $fatal(1, "SIZING FAIL: %0s", Message);
        end
    endtask

    initial begin
        $display("SIZING bits destination/expression: 64x32=%0d/%0d 64x64=%0d/%0d signed44x31=%0d/%0d chain=%0d",
                 $bits(Product_64x32), $bits(U64_A * U32),
                 $bits(Product_64x64), $bits(U64_A * U64_B),
                 $bits(Product_S44xS31), $bits(S44 * S31),
                 $bits(3 * S64_A * S64_B));

        require($bits(Product_64x32) == 96, "64x32 destination width");
        require($bits(Product_64x64) == 128, "64x64 destination width");
        require($bits(Product_S44xS31) == 75, "signed 44x31 destination width");
        require($bits(Chained_Signed) == 64, "signed chained destination width");
        require($bits(Signed_Slice) == 31, "part-select destination width");
        require($bits(Signed_Shift) == 100, "signed shift width");
        require($bits(Negated_Signed_Shift) == 100, "unary-minus width");
        require($bits(G_Product) == 66, "FINAL G_Product width");
        require($bits(DL) == 96, "FINAL DL width");
        require($bits(RX) == 128, "FINAL RX width");
        require($bits(GD) == 96, "FINAL GD width");

        U64_A = 64'hffffffffffffffff;
        U64_B = 64'hffffffffffffffff;
        U32 = 32'hffffffff;
        S44 = -44'sd1234567;
        S31 = 31'sd7654321;
        S64_A = -64'sd7;
        S64_B = 64'sd11;
        Unsigned_Packed = {80{1'b1}};
        Shift_Base = 100'sd3;
        Shift_Amount = 70;
        RH33 = 33'h1ffffffff;
        VH33 = 33'h1ffffffff;
        Divisor = 64'hffffffffffffffff;
        Low = 32'hffffffff;
        Reciprocal_Remainder = 64'hffffffffffffffff;
        Dividend_Hi = 64'hffffffffffffffff;
        G = 32'hffffffff;
        Carry_Low = 1'b0;
        #1;

        require(Product_64x32 === 96'hfffffffeffffffff00000001,
                "64x32 value is not truncated before 96-bit destination");
        require(Product_64x64 === 128'hfffffffffffffffe0000000000000001,
                "64x64 value in 128-bit destination");
        require(Product_S44xS31 === 75'h7fffffff767cdb09fa9,
                "signed 44x31 representative value");
        require(Chained_Signed === -64'sd231,
                "3 * signed64 * signed64 representative value");
        require(Signed_Slice === -31'sd1,
                "unsigned part-select interpreted through signed destination");
        require(Signed_Shift === 100'h0000000c00000000000000000,
                "signed W-bit left shift value");
        require(Negated_Signed_Shift === 100'hfffffff400000000000000000,
                "unary minus after signed W-bit left shift");
        require(G_Product === 66'h3fffffffc00000001, "FINAL 33x33 value");
        require(DL === 96'hfffffffeffffffff00000001, "FINAL 64x32 value");
        require(RX === 128'hfffffffffffffffe0000000000000001, "FINAL 64x64 value");
        require(GD === 96'hfffffffeffffffff00000001, "FINAL 32x64 value");

        require(Candidate_M[0] === -4'sd1,
                "k=0 Carry_Low=0 encodes signed -1");
        for (Index = 1; Index < 5; Index = Index + 1)
            require(Candidate_M[Index] === Index - 1,
                    "Carry_Low=0 candidate encoding");

        Carry_Low = 1'b1;
        #1;
        for (Index = 0; Index < 5; Index = Index + 1)
            require(Candidate_M[Index] === Index,
                    "Carry_Low=1 candidate encoding");

        require(!$isunknown({Product_64x32, Product_64x64, Product_S44xS31,
                            Chained_Signed, Signed_Slice, Signed_Shift,
                            Negated_Signed_Shift, G_Product, DL, RX, GD}),
                "representative expressions contain X/Z");
        $display("PASS SystemVerilog expression-sizing microtests");
        $finish;
    end
endmodule

`default_nettype wire
