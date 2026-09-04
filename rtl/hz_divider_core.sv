`default_nettype none

module hz_divider_core #(
    parameter integer VARIANT = 36
) (
    input  wire Clk,
    input  wire Reset_N,
    input  wire In_Valid,
    input  wire [63:0] Dividend_Hi,
    input  wire [63:0] Divisor,
    output reg  Out_Valid,
    output reg  Out_Error,
    output reg  [63:0] Quotient,
    output reg  [63:0] Remainder
);
    wire Input_Error = !Divisor[63] || (Dividend_Hi >= Divisor);
    wire [95:0] Prep_NX;
    wire [63:0] Prep_R;
    wire [79:0] Debug_S;
    wire [79:0] Debug_C;
    wire signed [7:0] Debug_Wrap;

    hz_prep #(.VARIANT(VARIANT)) u_prep (
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .NX(Prep_NX), .Reciprocal_Remainder(Prep_R),
        .Debug_Pred_S(Debug_S), .Debug_Pred_C(Debug_C), .Debug_Pred_Wrap(Debug_Wrap)
    );

    reg Stage1_Valid;
    reg Stage1_Error;
    reg [95:0] Stage1_NX;
    reg [63:0] Stage1_R;
    reg [63:0] Stage1_X;
    reg [63:0] Stage1_D;
    wire [63:0] Final_Q;
    wire [63:0] Final_R;

    hz_final u_final (
        .NX(Stage1_NX), .Reciprocal_Remainder(Stage1_R),
        .Dividend_Hi(Stage1_X), .Divisor(Stage1_D),
        .Quotient(Final_Q), .Remainder(Final_R)
    );

    always @(posedge Clk or negedge Reset_N) begin
        if (!Reset_N) begin
            Stage1_Valid <= 1'b0;
            Stage1_Error <= 1'b0;
            Stage1_NX <= 96'd0;
            Stage1_R <= 64'd0;
            Stage1_X <= 64'd0;
            Stage1_D <= 64'h8000000000000000;
            Out_Valid <= 1'b0;
            Out_Error <= 1'b0;
            Quotient <= 64'd0;
            Remainder <= 64'd0;
        end else begin
            Stage1_Valid <= In_Valid;
            Stage1_Error <= Input_Error;
            if (In_Valid) begin
                Stage1_NX <= Input_Error ? 96'd0 : Prep_NX;
                Stage1_R <= Input_Error ? 64'd0 : Prep_R;
                Stage1_X <= Dividend_Hi;
                Stage1_D <= Divisor;
            end
            Out_Valid <= Stage1_Valid;
            Out_Error <= Stage1_Error;
            if (Stage1_Valid) begin
                Quotient <= Stage1_Error ? 64'd0 : Final_Q;
                Remainder <= Stage1_Error ? 64'd0 : Final_R;
            end
        end
    end
endmodule

module divider_v36rcm (
    input wire Clk, input wire Reset_N, input wire In_Valid,
    input wire [63:0] Dividend_Hi, input wire [63:0] Divisor,
    output wire Out_Valid, output wire Out_Error,
    output wire [63:0] Quotient, output wire [63:0] Remainder
);
    hz_divider_core #(.VARIANT(36)) u_core (.*);
endmodule

module divider_v39c42 (
    input wire Clk, input wire Reset_N, input wire In_Valid,
    input wire [63:0] Dividend_Hi, input wire [63:0] Divisor,
    output wire Out_Valid, output wire Out_Error,
    output wire [63:0] Quotient, output wire [63:0] Remainder
);
    hz_divider_core #(.VARIANT(39)) u_core (.*);
endmodule

module divider_v43sj17 (
    input wire Clk, input wire Reset_N, input wire In_Valid,
    input wire [63:0] Dividend_Hi, input wire [63:0] Divisor,
    output wire Out_Valid, output wire Out_Error,
    output wire [63:0] Quotient, output wire [63:0] Remainder
);
    hz_divider_core #(.VARIANT(43)) u_core (.*);
endmodule

`default_nettype wire
