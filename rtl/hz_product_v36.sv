`default_nettype none

// Signed-safe realization of the V36 binary redundant-cut product.
// The original 66-row estimate assumed two unsigned 33-bit cut rows.  The
// actual V33 predictor is signed, so this implementation retains 68 binary
// rows plus one explicit wrap/sign correction row.
module hz_product_v36 #(
    parameter integer W = 100
) (
    input  wire [33:0] U,
    input  wire [33:0] V,
    input  wire signed [7:0] Wrap,
    input  wire [63:0] X,
    output wire [W-1:0] Sum,
    output wire [W-1:0] Carry
);
    wire [W-1:0] X_Ext = {{(W-64){1'b0}}, X};
    wire [69*W-1:0] Rows_Flat;

    genvar i;
    generate
        for (i = 0; i < 34; i = i + 1) begin : g_u_rows
            assign Rows_Flat[i*W +: W] = U[i] ? (X_Ext << i) : {W{1'b0}};
        end
        for (i = 0; i < 34; i = i + 1) begin : g_v_rows
            assign Rows_Flat[(34+i)*W +: W] = V[i] ? (X_Ext << i) : {W{1'b0}};
        end
    endgenerate

    wire signed [9:0] Top_Coeff = $signed(Wrap)
                                       - $signed({9'b0, U[33]})
                                       - $signed({9'b0, V[33]});
    wire signed [W+9:0] Top_Product = Top_Coeff * $signed({1'b0, X});
    assign Rows_Flat[68*W +: W] = Top_Product <<< 34;

    hz_reduce_69 #(.W(W)) u_reduce (
        .Rows_Flat(Rows_Flat), .Sum(Sum), .Carry(Carry)
    );
endmodule

`default_nettype wire
