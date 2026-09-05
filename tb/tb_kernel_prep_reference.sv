`timescale 1ns/1ps
`default_nettype none

module tb_kernel_prep_reference;
    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg [79:0] Pred_S = 80'd0;
    reg [79:0] Pred_C = 80'd0;
    reg signed [7:0] Pred_Wrap = 8'sd0;
    reg Carry_Low = 1'b0;
    reg [2:0] Candidate_K = 3'd0;
    reg [63:0] X = 64'd0;
    reg [63:0] D = 64'h8000_0000_0000_0000;

    wire [67:0] R36_5, R36_6, R43_5, R43_6;
    wire [99:0] N36_5, N36_6, N43_5, N43_6;

    kernel_v36rcm u_v36_5 (
        .Clk(Clk), .Reset_N(Reset_N), .Pred_S(Pred_S), .Pred_C(Pred_C),
        .Pred_Wrap(Pred_Wrap), .Carry_Low(Carry_Low),
        .Candidate_K(Candidate_K), .X(X), .D(D),
        .Residual_Path(R36_5), .NX_Path(N36_5)
    );
    kernel_v36rcm_prep6_ref u_v36_6 (
        .Clk(Clk), .Reset_N(Reset_N), .Pred_S(Pred_S), .Pred_C(Pred_C),
        .Pred_Wrap(Pred_Wrap), .Carry_Low(Carry_Low),
        .Candidate_K(Candidate_K), .X(X), .D(D),
        .Residual_Path(R36_6), .NX_Path(N36_6)
    );
    kernel_v43sj17 u_v43_5 (
        .Clk(Clk), .Reset_N(Reset_N), .Pred_S(Pred_S), .Pred_C(Pred_C),
        .Pred_Wrap(Pred_Wrap), .Carry_Low(Carry_Low),
        .Candidate_K(Candidate_K), .X(X), .D(D),
        .Residual_Path(R43_5), .NX_Path(N43_5)
    );
    kernel_v43sj17_prep6_ref u_v43_6 (
        .Clk(Clk), .Reset_N(Reset_N), .Pred_S(Pred_S), .Pred_C(Pred_C),
        .Pred_Wrap(Pred_Wrap), .Carry_Low(Carry_Low),
        .Candidate_K(Candidate_K), .X(X), .D(D),
        .Residual_Path(R43_6), .NX_Path(N43_6)
    );

    always #5 Clk = ~Clk;

    task drive_and_compare_legal;
        input [2:0] k;
        input carry;
        begin
            @(negedge Clk);
            Candidate_K = k;
            Carry_Low = carry;
            @(posedge Clk);
            #1;
            if ({R36_5, N36_5} !== {R36_6, N36_6})
                $fatal(1, "V36 PREP5/PREP6 mismatch for legal k=%0d carry=%0d", k, carry);
            if ({R43_5, N43_5} !== {R43_6, N43_6})
                $fatal(1, "V43 PREP5/PREP6 mismatch for legal k=%0d carry=%0d", k, carry);
        end
    endtask

    integer sample;
    integer k;
    integer carry;
    reg [67:0] five_d;
    reg [99:0] five_x;
    initial begin
        repeat (2) @(posedge Clk);
        Reset_N = 1'b1;
        for (sample = 0; sample < 32; sample = sample + 1) begin
            Pred_S = 80'h2345_6789_abcd_ef01_2345 + sample * 80'h1010_1010_1010_1010_1010;
            Pred_C = 80'hfedc_ba98_7654_3210_fedc ^ sample * 80'h0101_1010_0110_1001_1010;
            Pred_Wrap = sample - 16;
            X = 64'h0123_4567_89ab_cdef + sample * 64'h0101_0101_0101_0101;
            D = 64'h8000_0000_0000_0001 + sample * 64'h0010_0000_0000_0111;
            for (carry = 0; carry < 2; carry = carry + 1)
                for (k = 0; k < 5; k = k + 1)
                    drive_and_compare_legal(k[2:0], carry[0]);
        end

        // Candidate 5 is outside PREP5 but must exactly restore the historical
        // 5*D/5*X helper in the PREP6 reference mode.
        @(negedge Clk);
        Candidate_K = 3'd5;
        Carry_Low = 1'b1;
        @(posedge Clk);
        #1;
        five_d = {4'b0, D} + ({4'b0, D} << 2);
        five_x = {36'b0, X} + ({36'b0, X} << 2);
        if (R36_6 !== R36_5 - five_d || N36_6 !== N36_5 + five_x)
            $fatal(1, "V36 PREP6 reference did not restore M=5");
        if (R43_6 !== R43_5 - five_d || N43_6 !== N43_5 + five_x)
            $fatal(1, "V43 PREP6 reference did not restore M=5");

        $display("KERNEL_PREP_REFERENCE_PASS legal_pair_checks=%0d", 32 * 2 * 5 * 2);
        $finish;
    end
endmodule

`default_nettype wire
