`timescale 1ns/1ps
`default_nettype none

// Audit-only compiled check of the composed frozen-common mapped netlist.
// Correction labels are established by tb_full_prep.sv; this test observes
// only the real registered boundary available after standard-cell mapping.
module tb_full_prep_gate;
    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg [63:0] Dividend_Hi = 64'd0;
    reg [63:0] Divisor = 64'h8000000000000000;
    wire [95:0] NX;
    wire [63:0] Reciprocal_Remainder;

    integer Checked = 0;
    integer Tests = 32;
    integer Index;
    integer Variant = 0;
    reg [63:0] State = 64'h5eed36434344cafe;
    reg [63:0] Random_D;
    reg [63:0] Random_X;

    full_prep_v44 dut (
        .Clk(Clk),
        .Reset_N(Reset_N),
        .Dividend_Hi(Dividend_Hi),
        .Divisor(Divisor),
        .NX(NX),
        .Reciprocal_Remainder(Reciprocal_Remainder)
    );

    always #5 Clk = ~Clk;

    task automatic run_vector;
        input [63:0] This_X;
        input [63:0] This_D;
        reg [127:0] One96;
        reg [127:0] Exact_N;
        reg [127:0] Exact_R;
        reg [127:0] Exact_NX;
        begin
            if (!This_D[63] || This_X >= This_D)
                $fatal(1, "illegal mapped full-PREP vector");
            One96 = 128'd1 << 96;
            Exact_N = One96 / This_D;
            Exact_R = One96 - Exact_N * This_D;
            Exact_NX = Exact_N * This_X;

            @(negedge Clk);
            Dividend_Hi = This_X;
            Divisor = This_D;
            @(posedge Clk);
            #1;
            if (Reciprocal_Remainder !== Exact_R[63:0]) begin
                $display("GATE FAIL V%0d X=%016x D=%016x R=%016x expected=%016x",
                         Variant, This_X, This_D, Reciprocal_Remainder,
                         Exact_R[63:0]);
                $fatal(1);
            end
            if (NX !== Exact_NX[95:0]) begin
                $display("GATE FAIL V%0d X=%016x D=%016x NX=%024x expected=%024x",
                         Variant, This_X, This_D, NX, Exact_NX[95:0]);
                $fatal(1);
            end
            // Deliberately variant-neutral: compare_mapped requires byte-
            // identical traces from independently compiled V36/V43 netlists.
            $display("GATE_VECTOR %0d %016x %016x %024x %016x",
                     Checked, This_X, This_D, NX, Reciprocal_Remainder);
            Checked = Checked + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("VARIANT=%d", Variant))
            $fatal(1, "VARIANT plusarg is required");
        if (!$value$plusargs("TESTS=%d", Tests)) Tests = 32;
        if ((Variant != 36 && Variant != 43) || Tests < 0 || Tests > 256)
            $fatal(1, "invalid gate-test configuration");

        repeat (2) @(posedge Clk);
        #1;
        if (NX !== 96'd0 || Reciprocal_Remainder !== 64'd0)
            $fatal(1, "mapped asynchronous reset did not clear outputs");
        @(negedge Clk);
        Reset_N = 1'b1;

        // Exact correction witnesses 0,1,2,3,4 from the source-level gate.
        run_vector(64'd9340465626629537791, 64'd9340465626629537792);
        run_vector(64'd9232379236109516798, 64'd9232379236109516799);
        run_vector(64'd10377810952591741379, 64'd10377810952591741380);
        run_vector(64'd9223372036854775808, 64'd9223372036854775809);
        run_vector(64'd9232379236109516800, 64'd9232379236109516801);

        // Power special, maximum D, X=0, and X=D-1.
        run_vector(64'd0, 64'h8000000000000000);
        run_vector(64'h7fffffffffffffff, 64'h8000000000000000);
        run_vector(64'd0, 64'hffffffffffffffff);
        run_vector(64'hfffffffffffffffe, 64'hffffffffffffffff);

        for (Index = 0; Index < Tests; Index = Index + 1) begin
            State = State * 64'd6364136223846793005 +
                    64'd1442695040888963407;
            Random_D = State | 64'h8000000000000000;
            State = State * 64'd6364136223846793005 +
                    64'd1442695040888963407;
            Random_X = State;
            if (Random_X >= Random_D) Random_X = Random_X - Random_D;
            run_vector(Random_X, Random_D);
        end

        $display("PASS mapped full-PREP V%0d exact registered vectors=%0d",
                 Variant, Checked);
        $finish;
    end
endmodule

`default_nettype wire
