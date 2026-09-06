`default_nettype none

// Experiment-only register boundary around the byte-locked production PREP5
// arithmetic.  The same module/top/ports are used for VARIANT=36 and 43.
// FINAL, transaction/error control and pass-through X/D registers are outside
// this first full-PREP integration checkpoint.
module full_prep_v44 #(
    parameter integer VARIANT = 36
) (
    input  wire Clk,
    input  wire Reset_N,
    input  wire [63:0] Dividend_Hi,
    input  wire [63:0] Divisor,
    output reg  [95:0] NX,
    output reg  [63:0] Reciprocal_Remainder
);
    wire [95:0] Prep_NX;
    wire [63:0] Prep_R;
    wire [79:0] Debug_Pred_S;
    wire [79:0] Debug_Pred_C;
    wire signed [7:0] Debug_Pred_Wrap;

    hz_prep #(.VARIANT(VARIANT)) u_prep (
        .Dividend_Hi(Dividend_Hi),
        .Divisor(Divisor),
        .NX(Prep_NX),
        .Reciprocal_Remainder(Prep_R),
        .Debug_Pred_S(Debug_Pred_S),
        .Debug_Pred_C(Debug_Pred_C),
        .Debug_Pred_Wrap(Debug_Pred_Wrap)
    );

    always @(posedge Clk or negedge Reset_N) begin
        if (!Reset_N) begin
            NX <= 96'd0;
            Reciprocal_Remainder <= 64'd0;
        end else begin
            NX <= Prep_NX;
            Reciprocal_Remainder <= Prep_R;
        end
    end
endmodule

`default_nettype wire
