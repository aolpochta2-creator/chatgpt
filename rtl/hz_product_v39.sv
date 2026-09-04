`default_nettype none

module hz_product_v39 #(
    parameter integer W = 100
) (
    input  wire [33:0] U,
    input  wire [33:0] V,
    input  wire signed [7:0] Wrap,
    input  wire [63:0] X,
    output wire [W-1:0] Sum,
    output wire [W-1:0] Carry
);
    wire [35:0] U_Ext = {U[33], U, 1'b0};
    wire [35:0] V_Ext = {V[33], V, 1'b0};
    wire [35*W-1:0] Rows_Flat;

    function automatic [W-1:0] booth_row;
        input [2:0] Code;
        input [63:0] Multiplicand;
        input integer Shift;
        reg signed [W-1:0] Base;
        begin
            Base = $signed({{(W-64){1'b0}}, Multiplicand});
            case (Code)
                3'b001, 3'b010: booth_row = Base <<< Shift;
                3'b011:         booth_row = Base <<< (Shift + 1);
                3'b100:         booth_row = -(Base <<< (Shift + 1));
                3'b101, 3'b110: booth_row = -(Base <<< Shift);
                default:        booth_row = {W{1'b0}};
            endcase
        end
    endfunction

    genvar i;
    generate
        for (i = 0; i < 17; i = i + 1) begin : g_u_booth
            assign Rows_Flat[i*W +: W] = booth_row(U_Ext[2*i +: 3], X, 2*i);
        end
        for (i = 0; i < 17; i = i + 1) begin : g_v_booth
            assign Rows_Flat[(17+i)*W +: W] = booth_row(V_Ext[2*i +: 3], X, 2*i);
        end
    endgenerate

    wire signed [W+7:0] Wrap_Product = $signed(Wrap) * $signed({1'b0, X});
    assign Rows_Flat[34*W +: W] = Wrap_Product <<< 34;

    hz_reduce_35 #(.W(W)) u_reduce (
        .Rows_Flat(Rows_Flat), .Sum(Sum), .Carry(Carry)
    );
endmodule

`default_nettype wire
