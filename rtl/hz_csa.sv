`default_nettype none

module hz_csa3 #(
    parameter integer W = 80
) (
    input  wire [W-1:0] A,
    input  wire [W-1:0] B,
    input  wire [W-1:0] C,
    output wire [W-1:0] Sum,
    output wire [W-1:0] Carry
);
    wire [W-1:0] Majority = (A & B) | (A & C) | (B & C);
    assign Sum = A ^ B ^ C;
    assign Carry = {Majority[W-2:0], 1'b0};
endmodule

module hz_csa3_signed_wrap #(
    parameter integer W = 80,
    parameter integer WW = 8
) (
    input  wire [W-1:0] A,
    input  wire [W-1:0] B,
    input  wire [W-1:0] C,
    input  wire signed [WW-1:0] Wrap_A,
    input  wire signed [WW-1:0] Wrap_B,
    input  wire signed [WW-1:0] Wrap_C,
    output wire [W-1:0] Sum,
    output wire [W-1:0] Carry,
    output wire signed [WW-1:0] Wrap_Out
);
    wire [W-1:0] Majority = (A & B) | (A & C) | (B & C);
    wire Carry_Out = Majority[W-1];
    wire signed [WW-1:0] V_Carry_Out = {{(WW-1){1'b0}}, Carry_Out};
    wire signed [WW-1:0] V_A_Sign = {{(WW-1){1'b0}}, A[W-1]};
    wire signed [WW-1:0] V_B_Sign = {{(WW-1){1'b0}}, B[W-1]};
    wire signed [WW-1:0] V_C_Sign = {{(WW-1){1'b0}}, C[W-1]};
    wire signed [WW-1:0] V_Sum_Sign = {{(WW-1){1'b0}}, Sum[W-1]};
    wire signed [WW-1:0] V_Carry_Sign = {{(WW-1){1'b0}}, Carry[W-1]};

    assign Sum = A ^ B ^ C;
    assign Carry = {Majority[W-2:0], 1'b0};
    assign Wrap_Out = Wrap_A + Wrap_B + Wrap_C
                    + V_Carry_Out - V_A_Sign - V_B_Sign - V_C_Sign
                    + V_Sum_Sign + V_Carry_Sign;
endmodule

`default_nettype wire
