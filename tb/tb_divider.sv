`timescale 1ns/1ps
`default_nettype none

`ifndef DUT_MODULE
`define DUT_MODULE divider_v36rcm
`endif

module tb_divider;
    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg In_Valid = 1'b0;
    reg [63:0] Dividend_Hi = 64'd0;
    reg [63:0] Divisor = 64'h8000000000000000;
    wire Out_Valid;
    wire Out_Error;
    wire [63:0] Quotient;
    wire [63:0] Remainder;

    integer Seed;
    integer Tests;
    integer Index;
    reg [63:0] Test_D;
    reg [63:0] Test_X;

    `DUT_MODULE u_dut (
        .Clk(Clk), .Reset_N(Reset_N), .In_Valid(In_Valid),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .Out_Valid(Out_Valid), .Out_Error(Out_Error),
        .Quotient(Quotient), .Remainder(Remainder)
    );

    always #5 Clk = ~Clk;

    function automatic [63:0] random64;
        begin
            random64 = {$urandom, $urandom};
        end
    endfunction

    task automatic run_vector;
        input [63:0] X;
        input [63:0] D;
        reg [127:0] Wide_Numerator;
        reg [127:0] Wide_Quotient;
        reg [63:0] Expected_Q;
        reg [63:0] Expected_R;
        begin
            Wide_Numerator = {X, 64'b0};
            Wide_Quotient = Wide_Numerator / D;
            Expected_Q = Wide_Quotient[63:0];
            Expected_R = Wide_Numerator % D;
            @(negedge Clk);
            Dividend_Hi = X;
            Divisor = D;
            In_Valid = 1'b1;
            @(negedge Clk);
            In_Valid = 1'b0;
            while (!Out_Valid)
                @(negedge Clk);
            if (Out_Error || Quotient !== Expected_Q || Remainder !== Expected_R) begin
                $display("FAIL X=%016x D=%016x Q=%016x expected=%016x R=%016x expected=%016x error=%b",
                         X, D, Quotient, Expected_Q, Remainder, Expected_R, Out_Error);
                $fatal(1);
            end
        end
    endtask

    initial begin
        Seed = 32'h563943;
        Tests = 2000;
        if (!$value$plusargs("SEED=%d", Seed)) Seed = 32'h563943;
        if (!$value$plusargs("TESTS=%d", Tests)) Tests = 2000;
        Seed = $urandom(Seed);
        repeat (4) @(negedge Clk);
        Reset_N = 1'b1;

        run_vector(64'd0, 64'h8000000000000000);
        run_vector(64'h7fffffffffffffff, 64'h8000000000000000);
        run_vector(64'd0, 64'hffffffffffffffff);
        run_vector(64'hfffffffffffffffe, 64'hffffffffffffffff);
        run_vector(64'h4000000000000000, 64'h8000000000000001);

        for (Index = 0; Index < Tests; Index = Index + 1) begin
            Test_D = random64() | 64'h8000000000000000;
            Test_X = random64();
            if (Test_X >= Test_D)
                Test_X = Test_X - Test_D;
            run_vector(Test_X, Test_D);
        end
        $display("PASS vectors=%0d", Tests + 5);
        $finish;
    end
endmodule

`default_nettype wire
