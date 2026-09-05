`default_nettype none

// ROM-excluded comparison boundary for the only datapath region that differs
// between V36, V39 and V43.  Inputs are the signed V33 predictor CSA state.
module hz_kernel_core #(
    parameter integer VARIANT = 36
) (
    input  wire Clk,
    input  wire Reset_N,
    input  wire [79:0] Pred_S,
    input  wire [79:0] Pred_C,
    input  wire signed [7:0] Pred_Wrap,
    input  wire Carry_Low,
    // Candidate_K is three bits because the legal PREP range is 0..4.
    // Encodings 5..7 are outside the comparison-kernel contract.
    input  wire [2:0] Candidate_K,
    input  wire [63:0] X,
    input  wire [63:0] D,
    output reg  [67:0] Residual_Path,
    output reg  [99:0] NX_Path
);
    wire [33:0] U = Pred_S[79:46];
    wire [33:0] V = Pred_C[79:46];
    wire [67:0] PD_S, PD_C;
    wire [99:0] PX_S, PX_C;

    generate
        if (VARIANT == 36) begin : g_v36
            hz_product_v36 #(.W(68)) u_pd (.U(U), .V(V), .Wrap(Pred_Wrap), .X(D), .Sum(PD_S), .Carry(PD_C));
            hz_product_v36 #(.W(100)) u_px (.U(U), .V(V), .Wrap(Pred_Wrap), .X(X), .Sum(PX_S), .Carry(PX_C));
        end else if (VARIANT == 39) begin : g_v39
            hz_product_v39 #(.W(68)) u_pd (.U(U), .V(V), .Wrap(Pred_Wrap), .X(D), .Sum(PD_S), .Carry(PD_C));
            hz_product_v39 #(.W(100)) u_px (.U(U), .V(V), .Wrap(Pred_Wrap), .X(X), .Sum(PX_S), .Carry(PX_C));
        end else begin : g_v43
            hz_product_v43 #(.W(68)) u_pd (.U(U), .V(V), .X(D), .Sum(PD_S), .Carry(PD_C));
            hz_product_v43 #(.W(100)) u_px (.U(U), .V(V), .X(X), .Sum(PX_S), .Carry(PX_C));
        end
    endgenerate

    wire signed [3:0] M = Carry_Low ? $signed({1'b0, Candidate_K})
                                             : $signed({1'b0, Candidate_K}) - 4'sd1;
    reg [67:0] MD;
    reg [99:0] MX;
    wire [67:0] D_Base = {4'b0, D};
    wire [99:0] X_Base = {36'b0, X};
    always @* begin
        case (M)
            -4'sd1: begin MD = -D_Base; MX = -X_Base; end
             4'sd0: begin MD = 68'd0; MX = 100'd0; end
             4'sd1: begin MD = D_Base; MX = X_Base; end
             4'sd2: begin MD = D_Base << 1; MX = X_Base << 1; end
             4'sd3: begin MD = D_Base + (D_Base << 1); MX = X_Base + (X_Base << 1); end
             4'sd4: begin MD = D_Base << 2; MX = X_Base << 2; end
             default: begin MD = 68'd0; MX = 100'd0; end
        endcase
    end

    wire [67:0] R_S, R_C;
    wire [99:0] N_S, N_C;
    hz_csa3 #(.W(68)) u_r_csa (.A(~PD_S), .B(~PD_C), .C(~MD), .Sum(R_S), .Carry(R_C));
    hz_csa3 #(.W(100)) u_n_csa (.A(PX_S), .B(PX_C), .C(MX), .Sum(N_S), .Carry(N_C));
    wire [67:0] Residual_Next = R_S + R_C + 68'd3;
    wire [99:0] NX_Next = N_S + N_C;

    always @(posedge Clk or negedge Reset_N) begin
        if (!Reset_N) begin
            Residual_Path <= 68'd0;
            NX_Path <= 100'd0;
        end else begin
            Residual_Path <= Residual_Next;
            NX_Path <= NX_Next;
        end
    end
endmodule

module kernel_v36rcm (
    input wire Clk, input wire Reset_N,
    input wire [79:0] Pred_S, input wire [79:0] Pred_C,
    input wire signed [7:0] Pred_Wrap, input wire Carry_Low,
    input wire [2:0] Candidate_K, input wire [63:0] X, input wire [63:0] D,
    output wire [67:0] Residual_Path, output wire [99:0] NX_Path
);
    hz_kernel_core #(.VARIANT(36)) u_core (.*);
endmodule

module kernel_v39c42 (
    input wire Clk, input wire Reset_N,
    input wire [79:0] Pred_S, input wire [79:0] Pred_C,
    input wire signed [7:0] Pred_Wrap, input wire Carry_Low,
    input wire [2:0] Candidate_K, input wire [63:0] X, input wire [63:0] D,
    output wire [67:0] Residual_Path, output wire [99:0] NX_Path
);
    hz_kernel_core #(.VARIANT(39)) u_core (.*);
endmodule

module kernel_v43sj17 (
    input wire Clk, input wire Reset_N,
    input wire [79:0] Pred_S, input wire [79:0] Pred_C,
    input wire signed [7:0] Pred_Wrap, input wire Carry_Low,
    input wire [2:0] Candidate_K, input wire [63:0] X, input wire [63:0] D,
    output wire [67:0] Residual_Path, output wire [99:0] NX_Path
);
    hz_kernel_core #(.VARIANT(43)) u_core (.*);
endmodule

`default_nettype wire
