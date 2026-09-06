`timescale 1ns/1ps
`default_nettype none

module tb_v43_directed;
    reg [33:0] Synthetic_U;
    reg [33:0] Synthetic_V;
    reg [63:0] Synthetic_X;
    wire [99:0] Synthetic_Sum;
    wire [99:0] Synthetic_Carry;

    reg [63:0] Actual_D;
    wire [79:0] Pred_S;
    wire [79:0] Pred_C;
    wire signed [7:0] Pred_Wrap;
    wire Pred_Carry_Low;
    wire Pred_Power_Boundary;
    wire [99:0] Actual_Sum;
    wire [99:0] Actual_Carry;

    integer Inner;
    integer Outer;
    integer Value;

    hz_product_v43 #(.W(100)) u_synthetic (
        .U(Synthetic_U), .V(Synthetic_V), .X(Synthetic_X),
        .Sum(Synthetic_Sum), .Carry(Synthetic_Carry)
    );

    hz_predictor_csa u_predictor (
        .Divisor(Actual_D), .Pred_S(Pred_S), .Pred_C(Pred_C),
        .Pred_Wrap(Pred_Wrap), .Carry_Low(Pred_Carry_Low),
        .Is_Power_Boundary(Pred_Power_Boundary)
    );

    hz_product_v43 #(.W(100)) u_actual (
        .U(Pred_S[79:46]), .V(Pred_C[79:46]), .X(64'h0123456789abcdef),
        .Sum(Actual_Sum), .Carry(Actual_Carry)
    );

    function automatic [5:0] expected_local;
        input integer Z;
        integer Rank;
        begin
            Rank = (Z <= 3) ? Z : Z - 1;
            expected_local = (6'b000001 << Rank) - 1'b1;
        end
    endfunction

    function automatic [5:0] expected_compose;
        input [5:0] Inner_T;
        input [5:0] Outer_T;
        begin
            expected_compose[0] = Outer_T[2] | (Outer_T[1] & Inner_T[0]) | (Outer_T[0] & Inner_T[3]);
            expected_compose[1] = Outer_T[2] | (Outer_T[1] & Inner_T[1]) | (Outer_T[0] & Inner_T[4]);
            expected_compose[2] = Outer_T[2] | (Outer_T[1] & Inner_T[2]) | (Outer_T[0] & Inner_T[5]);
            expected_compose[3] = Outer_T[5] | (Outer_T[4] & Inner_T[0]) | (Outer_T[3] & Inner_T[3]);
            expected_compose[4] = Outer_T[5] | (Outer_T[4] & Inner_T[1]) | (Outer_T[3] & Inner_T[4]);
            expected_compose[5] = Outer_T[5] | (Outer_T[4] & Inner_T[2]) | (Outer_T[3] & Inner_T[5]);
        end
    endfunction

    task automatic require;
        input Condition;
        input [8*96-1:0] Message;
        begin
            if (Condition !== 1'b1)
                $fatal(1, "V43 DIRECTED FAIL: %0s", Message);
        end
    endtask

    initial begin
        Synthetic_U = 34'd0;
        Synthetic_V = 34'd0;
        Synthetic_X = 64'hfedcba9876543210;
        Actual_D = 64'h806cae583ca65a72;
        #1;

        // Exhaustively compile and call the production local and compose
        // functions over their finite input tables.
        for (Value = 0; Value <= 6; Value = Value + 1)
            require(u_synthetic.local_therm(Value) === expected_local(Value),
                    "local_therm table mismatch");
        for (Inner = 0; Inner < 64; Inner = Inner + 1)
            for (Outer = 0; Outer < 64; Outer = Outer + 1)
                require(u_synthetic.compose_therm(Inner, Outer) ===
                        expected_compose(Inner, Outer),
                        "compose_therm table mismatch");

        require(u_synthetic.digit_from_g(4'd0) === 3'sd0, "G=0 digit");
        require(u_synthetic.digit_from_g(4'd1) === 3'sd1, "G=1 digit");
        require(u_synthetic.digit_from_g(4'd2) === 3'sd2, "G=2 digit");
        require(u_synthetic.digit_from_g(4'd3) === -3'sd1, "G=3 digit");
        require(u_synthetic.digit_from_g(4'd4) === 3'sd0, "G=4 digit");
        require(u_synthetic.digit_from_g(4'd5) === 3'sd1, "G=5 digit");
        require(u_synthetic.digit_from_g(4'd6) === 3'sd2, "G=6 digit");
        require(u_synthetic.digit_from_g(4'd7) === -3'sd1, "G=7 digit");
        require(u_synthetic.digit_from_g(4'd8) === 3'sd0, "G=8 maps to digit 0");

        // Synthetic audit state supplied by the finite-width audit. It is not
        // claimed to be reachable from the predictor. It produces G=8 at i=2.
        Synthetic_U = 34'h10000003f;
        Synthetic_V = 34'h00000003f;
        #1;
        require(u_synthetic.Carry_State[0] === 2'd0, "synthetic carry state 0");
        require(u_synthetic.Carry_State[1] === 2'd1, "synthetic carry state 1");
        require(u_synthetic.Carry_State[2] === 2'd2, "synthetic carry state 2");
        require(u_synthetic.Z[2] === 3'd6, "synthetic Z[2]");
        require(({1'b0, u_synthetic.Z[2]} +
                 {2'b0, u_synthetic.Carry_State[2]}) === 4'd8,
                "synthetic internal G=8");
        require(u_synthetic.Digit[2] === 3'sd0, "synthetic G=8 Digit=0");

        // Actual predictor witness from the audit: carry state 2 is reachable.
        require(Pred_S[79:46] === 34'h201b1d97d, "actual carry=2 witness U");
        require(Pred_C[79:46] === 34'h3fc9cdd05, "actual carry=2 witness V");
        require(Pred_Wrap === 8'sd1, "actual carry=2 witness wrap");
        require(u_actual.Carry_State[8] === 2'd2,
                "actual predictor D=9253963028337416818 reaches carry state 2");

        $display("PASS V43 local/compose tables, carry states 0/1/2, synthetic G=8, actual carry=2 witness");
        $finish;
    end
endmodule

`default_nettype wire
