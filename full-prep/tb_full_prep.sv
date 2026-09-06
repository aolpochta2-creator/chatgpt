`timescale 1ns/1ps
`default_nettype none

module tb_full_prep;
    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg [63:0] Dividend_Hi = 64'd0;
    reg [63:0] Divisor = 64'h8000000000000000;

    wire [95:0] V36_NX;
    wire [63:0] V36_R;
    wire [95:0] V43_NX;
    wire [63:0] V43_R;

    integer Seed;
    integer Tests;
    integer Checked;
    integer Index;
    reg [63:0] Random_D;
    reg [63:0] Random_X;

    full_prep_v44 #(.VARIANT(36)) u_v36 (
        .Clk(Clk), .Reset_N(Reset_N),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .NX(V36_NX), .Reciprocal_Remainder(V36_R)
    );
    full_prep_v44 #(.VARIANT(43)) u_v43 (
        .Clk(Clk), .Reset_N(Reset_N),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .NX(V43_NX), .Reciprocal_Remainder(V43_R)
    );

    always #5 Clk = ~Clk;

    function automatic [63:0] random64;
        begin
            random64 = {$urandom, $urandom};
        end
    endfunction

    task automatic fail;
        input [8*128-1:0] Message;
        begin
            $display("FULL-PREP FAIL vector=%0d X=%016x D=%016x: %0s",
                     Checked, Dividend_Hi, Divisor, Message);
            $display("V36 NX/R=%024x/%016x correction=%0d",
                     V36_NX, V36_R, u_v36.u_prep.Correction);
            $display("V43 NX/R=%024x/%016x correction=%0d",
                     V43_NX, V43_R, u_v43.u_prep.Correction);
            $fatal(1);
        end
    endtask

    task automatic run_vector;
        input [63:0] This_X;
        input [63:0] This_D;
        input integer Expected_Correction;
        reg [127:0] One96;
        reg [127:0] Exact_N;
        reg [127:0] Exact_R;
        reg [127:0] Exact_NX;
        begin
            if (!This_D[63] || This_X >= This_D)
                $fatal(1, "illegal full-PREP test vector X=%016x D=%016x",
                       This_X, This_D);

            One96 = 128'd1 << 96;
            Exact_N = One96 / This_D;
            Exact_R = One96 - Exact_N * This_D;
            Exact_NX = Exact_N * This_X;
            if (Exact_R[127:64] != 64'd0 || Exact_NX[127:96] != 32'd0)
                $fatal(1, "exact reference exceeded PREP output widths");

            @(negedge Clk);
            Dividend_Hi = This_X;
            Divisor = This_D;
            #1;

            // Observe the exact production combinational cone before its
            // experiment-only output register boundary.
            if (u_v36.u_prep.Reciprocal_Remainder !== Exact_R[63:0] ||
                u_v43.u_prep.Reciprocal_Remainder !== Exact_R[63:0])
                fail("selected combinational residual is not exact");
            if (u_v36.u_prep.NX !== Exact_NX[95:0] ||
                u_v43.u_prep.NX !== Exact_NX[95:0])
                fail("selected combinational NX is not exact");
            if (u_v36.u_prep.NX !== u_v43.u_prep.NX ||
                u_v36.u_prep.Reciprocal_Remainder !==
                    u_v43.u_prep.Reciprocal_Remainder)
                fail("V36/V43 production PREP combinational mismatch");

            if (Expected_Correction >= 0) begin
                if (u_v36.u_prep.Correction !== Expected_Correction ||
                    u_v43.u_prep.Correction !== Expected_Correction)
                    fail("directed PREP correction mismatch");
                case (Expected_Correction)
                    0: if (u_v36.u_prep.Residual_Candidate[0][67] ||
                           u_v43.u_prep.Residual_Candidate[0][67] ||
                           !u_v36.u_prep.Residual_Candidate[1][67] ||
                           !u_v43.u_prep.Residual_Candidate[1][67])
                           fail("correction-0 residual signs");
                    1: if (u_v36.u_prep.Residual_Candidate[1][67] ||
                           u_v43.u_prep.Residual_Candidate[1][67] ||
                           !u_v36.u_prep.Residual_Candidate[2][67] ||
                           !u_v43.u_prep.Residual_Candidate[2][67])
                           fail("correction-1 residual signs");
                    2: if (u_v36.u_prep.Residual_Candidate[2][67] ||
                           u_v43.u_prep.Residual_Candidate[2][67] ||
                           !u_v36.u_prep.Residual_Candidate[3][67] ||
                           !u_v43.u_prep.Residual_Candidate[3][67])
                           fail("correction-2 residual signs");
                    3: if (u_v36.u_prep.Residual_Candidate[3][67] ||
                           u_v43.u_prep.Residual_Candidate[3][67] ||
                           !u_v36.u_prep.Residual_Candidate[4][67] ||
                           !u_v43.u_prep.Residual_Candidate[4][67])
                           fail("correction-3 residual signs");
                    4: if (u_v36.u_prep.Residual_Candidate[4][67] ||
                           u_v43.u_prep.Residual_Candidate[4][67])
                           fail("correction-4 selected residual is negative");
                    default: fail("unexpected directed correction");
                endcase
            end

            @(posedge Clk);
            #1; // Explicit post-NBA observation at the PREP output boundary.
            if (V36_R !== Exact_R[63:0] || V43_R !== Exact_R[63:0])
                fail("registered residual is not exact");
            if (V36_NX !== Exact_NX[95:0] || V43_NX !== Exact_NX[95:0])
                fail("registered NX is not exact");
            if (V36_R !== V43_R || V36_NX !== V43_NX)
                fail("registered V36/V43 mismatch");
            Checked = Checked + 1;
        end
    endtask

    initial begin
        Seed = 32'hf011cafe;
        Tests = 256;
        Checked = 0;
        if (!$value$plusargs("SEED=%d", Seed)) Seed = 32'h36434344;
        if (!$value$plusargs("TESTS=%d", Tests)) Tests = 256;
        if (Tests < 0 || Tests > 100000)
            $fatal(1, "invalid TESTS=%0d", Tests);
        Seed = $urandom(Seed);

        repeat (2) @(posedge Clk);
        #1;
        if (V36_NX !== 96'd0 || V43_NX !== 96'd0 ||
            V36_R !== 64'd0 || V43_R !== 64'd0)
            fail("asynchronous reset did not clear output registers");
        @(negedge Clk);
        Reset_N = 1'b1;

        // Exact PREP correction range 0..4, including both endpoint witnesses.
        run_vector(64'd9340465626629537791, 64'd9340465626629537792, 0);
        run_vector(64'd9232379236109516798, 64'd9232379236109516799, 1);
        run_vector(64'd10377810952591741379, 64'd10377810952591741380, 2);
        run_vector(64'd9223372036854775808, 64'd9223372036854775809, 3);
        run_vector(64'd9232379236109516800, 64'd9232379236109516801, 4);

        // Power-boundary special, maximum divisor, X=0 and X=D-1.
        run_vector(64'd0, 64'h8000000000000000, -1);
        run_vector(64'h7fffffffffffffff, 64'h8000000000000000, -1);
        run_vector(64'd0, 64'hffffffffffffffff, 1);
        run_vector(64'hfffffffffffffffe, 64'hffffffffffffffff, 1);

        for (Index = 0; Index < Tests; Index = Index + 1) begin
            Random_D = random64() | 64'h8000000000000000;
            Random_X = random64();
            if (Random_X >= Random_D)
                Random_X = Random_X - Random_D;
            run_vector(Random_X, Random_D, -1);
        end

        // Flush with another exact boundary value so the last random result
        // has already crossed the registered observation point.
        run_vector(64'd0, 64'h8000000000000000, -1);
        $display("PASS full-PREP V36/V43 exact registered equivalence vectors=%0d corrections=0..4",
                 Checked);
        $finish;
    end
endmodule

`default_nettype wire
