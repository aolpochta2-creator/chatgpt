`default_nettype none

module hz_prep #(
    parameter integer VARIANT = 36
) (
    input  wire [63:0] Dividend_Hi,
    input  wire [63:0] Divisor,
    output reg  [95:0] NX,
    output reg  [63:0] Reciprocal_Remainder,
    output wire [79:0] Debug_Pred_S,
    output wire [79:0] Debug_Pred_C,
    output wire signed [7:0] Debug_Pred_Wrap
);
    wire [79:0] Pred_S;
    wire [79:0] Pred_C;
    wire signed [7:0] Pred_Wrap;
    wire Carry_Low;
    wire Is_Power_Boundary;
    wire [33:0] U = Pred_S[79:46];
    wire [33:0] V = Pred_C[79:46];

    hz_predictor_csa u_predictor (
        .Divisor(Divisor),
        .Pred_S(Pred_S), .Pred_C(Pred_C), .Pred_Wrap(Pred_Wrap),
        .Carry_Low(Carry_Low), .Is_Power_Boundary(Is_Power_Boundary)
    );
    assign Debug_Pred_S = Pred_S;
    assign Debug_Pred_C = Pred_C;
    assign Debug_Pred_Wrap = Pred_Wrap;

    wire [67:0] PD_S;
    wire [67:0] PD_C;
    wire [99:0] PX_S;
    wire [99:0] PX_C;

    generate
        if (VARIANT == 36) begin : g_v36
            hz_product_v36 #(.W(68)) u_pd (
                .U(U), .V(V), .Wrap(Pred_Wrap), .X(Divisor),
                .Sum(PD_S), .Carry(PD_C)
            );
            hz_product_v36 #(.W(100)) u_px (
                .U(U), .V(V), .Wrap(Pred_Wrap), .X(Dividend_Hi),
                .Sum(PX_S), .Carry(PX_C)
            );
        end else if (VARIANT == 39) begin : g_v39
            hz_product_v39 #(.W(68)) u_pd (
                .U(U), .V(V), .Wrap(Pred_Wrap), .X(Divisor),
                .Sum(PD_S), .Carry(PD_C)
            );
            hz_product_v39 #(.W(100)) u_px (
                .U(U), .V(V), .Wrap(Pred_Wrap), .X(Dividend_Hi),
                .Sum(PX_S), .Carry(PX_C)
            );
        end else begin : g_v43
            hz_product_v43 #(.W(68)) u_pd (
                .U(U), .V(V), .X(Divisor), .Sum(PD_S), .Carry(PD_C)
            );
            hz_product_v43 #(.W(100)) u_px (
                .U(U), .V(V), .X(Dividend_Hi), .Sum(PX_S), .Carry(PX_C)
            );
        end
    endgenerate

    function automatic [67:0] multiple68;
        input signed [3:0] M;
        input [63:0] X;
        reg [67:0] Base;
        begin
            Base = {4'b0, X};
            case (M)
                -4'sd1: multiple68 = -Base;
                 4'sd0: multiple68 = 68'd0;
                 4'sd1: multiple68 = Base;
                 4'sd2: multiple68 = Base << 1;
                 4'sd3: multiple68 = Base + (Base << 1);
                 4'sd4: multiple68 = Base << 2;
                 default: multiple68 = 68'd0;
            endcase
        end
    endfunction

    function automatic [99:0] multiple100;
        input signed [3:0] M;
        input [63:0] X;
        reg [99:0] Base;
        begin
            Base = {36'b0, X};
            case (M)
                -4'sd1: multiple100 = -Base;
                 4'sd0: multiple100 = 100'd0;
                 4'sd1: multiple100 = Base;
                 4'sd2: multiple100 = Base << 1;
                 4'sd3: multiple100 = Base + (Base << 1);
                 4'sd4: multiple100 = Base << 2;
                 default: multiple100 = 100'd0;
            endcase
        end
    endfunction

    // The V44 mathematical audit proves that floor(2^96 / D) - p is exactly
    // bounded by 0..4 on the legal non-boundary domain.  Five candidates are
    // therefore sufficient; p+5 is always negative in residual form.
    localparam integer PREP_CANDIDATES = 5;
    wire [67:0] Residual_Candidate [0:PREP_CANDIDATES-1];
    wire [99:0] NX_Candidate [0:PREP_CANDIDATES-1];
    genvar k;
    generate
        for (k = 0; k < PREP_CANDIDATES; k = k + 1) begin : g_candidate
            wire signed [3:0] M = Carry_Low ? k : k - 1;
            wire [67:0] MD = multiple68(M, Divisor);
            wire [99:0] MX = multiple100(M, Dividend_Hi);
            wire [67:0] R_S;
            wire [67:0] R_C;
            wire [99:0] N_S;
            wire [99:0] N_C;

            hz_csa3 #(.W(68)) u_residual_csa (
                .A(~PD_S), .B(~PD_C), .C(~MD), .Sum(R_S), .Carry(R_C)
            );
            assign Residual_Candidate[k] = R_S + R_C + 68'd3;

            hz_csa3 #(.W(100)) u_nx_csa (
                .A(PX_S), .B(PX_C), .C(MX), .Sum(N_S), .Carry(N_C)
            );
            assign NX_Candidate[k] = N_S + N_C;
        end
    endgenerate

    reg [2:0] Correction;
    reg [67:0] Selected_Residual;
    reg [99:0] Selected_NX;
    always @* begin
        Correction = 3'd0;
        if (!Residual_Candidate[1][67]) Correction = 3'd1;
        if (!Residual_Candidate[2][67]) Correction = 3'd2;
        if (!Residual_Candidate[3][67]) Correction = 3'd3;
        if (!Residual_Candidate[4][67]) Correction = 3'd4;
        case (Correction)
            3'd1: begin Selected_Residual = Residual_Candidate[1]; Selected_NX = NX_Candidate[1]; end
            3'd2: begin Selected_Residual = Residual_Candidate[2]; Selected_NX = NX_Candidate[2]; end
            3'd3: begin Selected_Residual = Residual_Candidate[3]; Selected_NX = NX_Candidate[3]; end
            3'd4: begin Selected_Residual = Residual_Candidate[4]; Selected_NX = NX_Candidate[4]; end
            default: begin Selected_Residual = Residual_Candidate[0]; Selected_NX = NX_Candidate[0]; end
        endcase

        if (Is_Power_Boundary) begin
            Reciprocal_Remainder = 64'd0;
            NX = {Dividend_Hi, 33'b0};
        end else begin
            Reciprocal_Remainder = Selected_Residual[63:0];
            NX = Selected_NX[95:0];
        end
    end
endmodule

`default_nettype wire
