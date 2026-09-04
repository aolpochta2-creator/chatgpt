`default_nettype none

// V43 signed-safe joint radix-4 product.  The 17 joint digits represent
// A = sh + ch + wrap*2^34 exactly; the proved top coefficient is zero, so
// Wrap is intentionally absent from this module's hardware interface.
module hz_product_v43 #(
    parameter integer W = 100
) (
    input  wire [33:0] U,
    input  wire [33:0] V,
    input  wire [63:0] X,
    output wire [W-1:0] Sum,
    output wire [W-1:0] Carry
);
    wire [2:0] Z [0:16];
    wire [5:0] P0 [0:15];
    wire [5:0] P1 [0:15];
    wire [5:0] P2 [0:15];
    wire [5:0] P3 [0:15];
    wire [5:0] P4 [0:15];
    wire [1:0] Carry_State [0:16];
    wire signed [2:0] Digit [0:16];
    wire [17*W-1:0] Rows_Flat;

    function automatic [5:0] local_therm;
        input [2:0] Value;
        reg [2:0] Rank;
        begin
            Rank = (Value <= 3) ? Value : Value - 1'b1;
            case (Rank)
                3'd0: local_therm = 6'b000000;
                3'd1: local_therm = 6'b000001;
                3'd2: local_therm = 6'b000011;
                3'd3: local_therm = 6'b000111;
                3'd4: local_therm = 6'b001111;
                3'd5: local_therm = 6'b011111;
                default: local_therm = 6'b111111;
            endcase
        end
    endfunction

    function automatic [5:0] compose_therm;
        input [5:0] Inner;
        input [5:0] Outer;
        begin
            compose_therm[0] = Outer[2] | (Outer[1] & Inner[0]) | (Outer[0] & Inner[3]);
            compose_therm[1] = Outer[2] | (Outer[1] & Inner[1]) | (Outer[0] & Inner[4]);
            compose_therm[2] = Outer[2] | (Outer[1] & Inner[2]) | (Outer[0] & Inner[5]);
            compose_therm[3] = Outer[5] | (Outer[4] & Inner[0]) | (Outer[3] & Inner[3]);
            compose_therm[4] = Outer[5] | (Outer[4] & Inner[1]) | (Outer[3] & Inner[4]);
            compose_therm[5] = Outer[5] | (Outer[4] & Inner[2]) | (Outer[3] & Inner[5]);
        end
    endfunction

    function automatic signed [2:0] digit_from_g;
        input [3:0] G;
        begin
            case (G)
                4'd0: digit_from_g = 3'sd0;
                4'd1: digit_from_g = 3'sd1;
                4'd2: digit_from_g = 3'sd2;
                4'd3: digit_from_g = -3'sd1;
                4'd4: digit_from_g = 3'sd0;
                4'd5: digit_from_g = 3'sd1;
                4'd6: digit_from_g = 3'sd2;
                4'd7: digit_from_g = -3'sd1;
                default: digit_from_g = 3'sd0;
            endcase
        end
    endfunction

    function automatic [W-1:0] digit_row;
        input signed [2:0] D;
        input [63:0] Multiplicand;
        input integer Shift;
        reg signed [W-1:0] Base;
        begin
            Base = $signed({{(W-64){1'b0}}, Multiplicand});
            case (D)
                -3'sd1: digit_row = -(Base <<< Shift);
                 3'sd1: digit_row = Base <<< Shift;
                 3'sd2: digit_row = Base <<< (Shift + 1);
                 default: digit_row = {W{1'b0}};
            endcase
        end
    endfunction

    genvar i;
    generate
        for (i = 0; i < 17; i = i + 1) begin : g_z
            assign Z[i] = {1'b0, U[2*i +: 2]} + {1'b0, V[2*i +: 2]};
        end
        for (i = 0; i < 16; i = i + 1) begin : g_prefix0
            assign P0[i] = local_therm(Z[i]);
        end
        for (i = 0; i < 16; i = i + 1) begin : g_prefix1
            if (i >= 1)
                assign P1[i] = compose_therm(P0[i-1], P0[i]);
            else
                assign P1[i] = P0[i];
        end
        for (i = 0; i < 16; i = i + 1) begin : g_prefix2
            if (i >= 2)
                assign P2[i] = compose_therm(P1[i-2], P1[i]);
            else
                assign P2[i] = P1[i];
        end
        for (i = 0; i < 16; i = i + 1) begin : g_prefix3
            if (i >= 4)
                assign P3[i] = compose_therm(P2[i-4], P2[i]);
            else
                assign P3[i] = P2[i];
        end
        for (i = 0; i < 16; i = i + 1) begin : g_prefix4
            if (i >= 8)
                assign P4[i] = compose_therm(P3[i-8], P3[i]);
            else
                assign P4[i] = P3[i];
        end
    endgenerate

    assign Carry_State[0] = 2'd0;
    generate
        for (i = 1; i < 17; i = i + 1) begin : g_carry
            assign Carry_State[i] = P4[i-1][5] ? 2'd2
                                  : P4[i-1][2] ? 2'd1 : 2'd0;
        end
        for (i = 0; i < 17; i = i + 1) begin : g_digit
            assign Digit[i] = digit_from_g({1'b0, Z[i]} + {2'b0, Carry_State[i]});
            assign Rows_Flat[i*W +: W] = digit_row(Digit[i], X, 2*i);
        end
    endgenerate

    hz_reduce_17 #(.W(W)) u_reduce (
        .Rows_Flat(Rows_Flat), .Sum(Sum), .Carry(Carry)
    );
endmodule

`default_nettype wire
