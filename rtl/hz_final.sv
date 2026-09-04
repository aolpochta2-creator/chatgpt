`default_nettype none

module hz_final (
    input  wire [95:0] NX,
    input  wire [63:0] Reciprocal_Remainder,
    input  wire [63:0] Dividend_Hi,
    input  wire [63:0] Divisor,
    output reg  [63:0] Quotient,
    output reg  [63:0] Remainder
);
    wire [63:0] Q0 = NX[95:32];
    wire [31:0] Low = NX[31:0];
    wire [32:0] RH33 = Reciprocal_Remainder[63:31];
    wire [32:0] VH33 = NX[95:63];
    wire [65:0] G_Product = RH33 * VH33;
    wire [31:0] G = G_Product[65:34];

    wire [95:0] DL = Divisor * Low;
    wire [127:0] RX = Reciprocal_Remainder * Dividend_Hi;
    wire [128:0] R0_Numerator = {33'b0, DL} + {1'b0, RX};
    wire [96:0] R0 = R0_Numerator[128:32];
    wire [95:0] GD = G * Divisor;
    wire signed [97:0] E = $signed({1'b0, R0}) - $signed({2'b0, GD});

    wire signed [97:0] R0_Candidate = E;
    wire signed [97:0] R1_Candidate = E - $signed({34'b0, Divisor});
    wire signed [97:0] R2_Candidate = E - $signed({33'b0, Divisor, 1'b0});
    wire signed [97:0] R3_Candidate = E - $signed({34'b0, Divisor})
                                             - $signed({33'b0, Divisor, 1'b0});

    reg [1:0] Correction;
    reg signed [97:0] Selected_Remainder;
    always @* begin
        Correction = 2'd0;
        Selected_Remainder = R0_Candidate;
        if (!R1_Candidate[97]) begin Correction = 2'd1; Selected_Remainder = R1_Candidate; end
        if (!R2_Candidate[97]) begin Correction = 2'd2; Selected_Remainder = R2_Candidate; end
        if (!R3_Candidate[97]) begin Correction = 2'd3; Selected_Remainder = R3_Candidate; end
        Quotient = Q0 + {32'b0, G} + {{62{1'b0}}, Correction};
        Remainder = Selected_Remainder[63:0];
    end
endmodule

`default_nettype wire
