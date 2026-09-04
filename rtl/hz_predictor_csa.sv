`default_nettype none

module hz_predictor_csa (
    input  wire [63:0] Divisor,
    output wire [79:0] Pred_S,
    output wire [79:0] Pred_C,
    output wire signed [7:0] Pred_Wrap,
    output wire Carry_Low,
    output wire Is_Power_Boundary
);
    wire [10:0] M = ((Divisor - 64'd1) >> 53) + 11'd1;
    wire [10:0] Bucket = M - 11'd1025;
    wire [5:0] Block = Bucket[9:4];
    wire [3:0] D_Local = Bucket[3:0];
    wire [64:0] Bucket_Top = {M, 53'b0};
    wire [52:0] E = Bucket_Top[63:0] - Divisor;
    wire [23:0] H1 = E[52:29];
    wire [12:0] H2 = E[52:40];
    wire [7:0] H3 = E[52:45];
    wire [7:0] H2_A = H2[12:5];
    wire [4:0] H2_B = H2[4:0];

    wire [52:0] C0;
    wire [42:0] C1;
    wire [32:0] C2;
    wire [22:0] C3;
    wire [12:0] C4;
    wire [2:0] C5;
    wire [15:0] Square_A;
    wire [9:0] Square_B;
    wire [23:0] Cube;

    hz_predictor_roms u_roms (
        .Block(Block),
        .Square_A_Address(H2_A),
        .Square_B_Address(H2_B),
        .Cube_Address(H3),
        .C0(C0), .C1(C1), .C2(C2), .C3(C3), .C4(C4), .C5(C5),
        .Square_A(Square_A), .Square_B(Square_B), .Cube(Cube)
    );

    wire [12:0] H2_AB = H2_A * H2_B;
    wire [25:0] Square = ({10'b0, Square_A} << 10)
                         + ({13'b0, H2_AB} << 6)
                         + {{16{1'b0}}, Square_B};
    wire [26:0] S0 = 27'd67108864;
    wire [25:0] S1 = {H1, 2'b0};
    wire [25:0] S2 = Square;
    wire [25:0] S3 = {Cube, 2'b0};

    wire [7:0] D2 = D_Local * D_Local;
    wire [11:0] D3 = D2 * D_Local;
    wire [15:0] D4 = D3 * D_Local;
    wire [19:0] D5 = D4 * D_Local;

    wire signed [63:0] DS = $signed({60'b0, D_Local});
    wire signed [63:0] D2S = $signed({56'b0, D2});
    wire signed [63:0] D3S = $signed({52'b0, D3});
    wire signed [63:0] D4S = $signed({48'b0, D4});
    wire signed [63:0] D5S = $signed({44'b0, D5});
    wire signed [63:0] S0S = $signed({37'b0, S0});
    wire signed [63:0] S1S = $signed({38'b0, S1});
    wire signed [63:0] S2S = $signed({38'b0, S2});
    wire signed [63:0] S3S = $signed({38'b0, S3});

    wire signed [63:0] W1_Wide = S1S - DS * S0S;
    wire signed [63:0] W2_Wide = D2S * S0S - (DS * S1S <<< 1) + S2S;
    wire signed [63:0] W3_Wide = -D3S * S0S + 3 * D2S * S1S
                               - 3 * DS * S2S + S3S;
    wire signed [63:0] W4_Wide = D4S * S0S - 4 * D3S * S1S
                               + 6 * D2S * S2S - 4 * DS * S3S;
    wire signed [63:0] W5_Wide = -D5S * S0S + 5 * D4S * S1S
                               - 10 * D3S * S2S + 10 * D2S * S3S;

    wire signed [30:0] W1 = W1_Wide[30:0];
    wire signed [34:0] W2 = W2_Wide[34:0];
    wire signed [38:0] W3 = W3_Wide[38:0];
    wire signed [42:0] W4 = W4_Wide[42:0];
    wire signed [46:0] W5 = W5_Wide[46:0];

    wire signed [74:0] Product1 = $signed({1'b0, C1}) * W1;
    wire signed [68:0] Product2 = $signed({1'b0, C2}) * W2;
    wire signed [62:0] Product3 = $signed({1'b0, C3}) * W3;
    wire signed [56:0] Product4 = $signed({1'b0, C4}) * W4;
    wire signed [50:0] Product5 = $signed({1'b0, C5}) * W5;

    wire [79:0] Term0 = {1'b0, C0, 26'b0};
    wire [79:0] Term1 = {{5{Product1[74]}}, Product1};
    wire [79:0] Term2 = {{11{Product2[68]}}, Product2};
    wire [79:0] Term3 = {{17{Product3[62]}}, Product3};
    wire [79:0] Term4 = {{23{Product4[56]}}, Product4};
    wire [79:0] Term5 = {{29{Product5[50]}}, Product5};

    wire [79:0] L1_S0, L1_C0, L1_S1, L1_C1;
    wire [79:0] L2_S, L2_C;
    wire signed [7:0] L1_W0, L1_W1, L2_W;
    wire signed [7:0] Zero_Wrap = 8'sd0;

    hz_csa3_signed_wrap u_csa_l1a (
        .A(Term0), .B(Term1), .C(Term2),
        .Wrap_A(Zero_Wrap), .Wrap_B(Zero_Wrap), .Wrap_C(Zero_Wrap),
        .Sum(L1_S0), .Carry(L1_C0), .Wrap_Out(L1_W0)
    );
    hz_csa3_signed_wrap u_csa_l1b (
        .A(Term3), .B(Term4), .C(Term5),
        .Wrap_A(Zero_Wrap), .Wrap_B(Zero_Wrap), .Wrap_C(Zero_Wrap),
        .Sum(L1_S1), .Carry(L1_C1), .Wrap_Out(L1_W1)
    );
    hz_csa3_signed_wrap u_csa_l2 (
        .A(L1_S0), .B(L1_C0), .C(L1_S1),
        .Wrap_A(Zero_Wrap), .Wrap_B(L1_W0), .Wrap_C(Zero_Wrap),
        .Sum(L2_S), .Carry(L2_C), .Wrap_Out(L2_W)
    );
    hz_csa3_signed_wrap u_csa_l3 (
        .A(L2_S), .B(L2_C), .C(L1_C1),
        .Wrap_A(Zero_Wrap), .Wrap_B(L2_W), .Wrap_C(L1_W1),
        .Sum(Pred_S), .Carry(Pred_C), .Wrap_Out(Pred_Wrap)
    );

    wire [46:0] Low_Add = {1'b0, Pred_S[45:0]} + {1'b0, Pred_C[45:0]};
    assign Carry_Low = Low_Add[46];
    assign Is_Power_Boundary = (Divisor == 64'h8000000000000000);
endmodule

`default_nettype wire
