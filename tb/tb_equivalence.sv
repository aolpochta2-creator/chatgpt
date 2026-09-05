`timescale 1ns/1ps
`default_nettype none

module tb_equivalence;
    localparam integer MAX_VECTORS = 100128;

    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg In_Valid = 1'b0;
    reg [63:0] Dividend_Hi = 64'd0;
    reg [63:0] Divisor = 64'h8000000000000000;
    wire V36_Valid, V39_Valid, V43_Valid;
    wire V36_Error, V39_Error, V43_Error;
    wire [63:0] V36_Q, V39_Q, V43_Q;
    wire [63:0] V36_R, V39_R, V43_R;

    integer Seed;
    integer Tests;
    integer Index;
    integer Vector_Count;
    integer Send_Index;
    integer Receive_Index;
    integer Cycles;
    reg [63:0] Test_D;
    reg [63:0] Test_X;
    reg [63:0] Vector_X [0:MAX_VECTORS-1];
    reg [63:0] Vector_D [0:MAX_VECTORS-1];
    reg [63:0] Expected_Q [0:MAX_VECTORS-1];
    reg [63:0] Expected_R [0:MAX_VECTORS-1];

    divider_v36rcm u_v36 (
        .Clk(Clk), .Reset_N(Reset_N), .In_Valid(In_Valid),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .Out_Valid(V36_Valid), .Out_Error(V36_Error),
        .Quotient(V36_Q), .Remainder(V36_R)
    );
    divider_v39c42 u_v39 (
        .Clk(Clk), .Reset_N(Reset_N), .In_Valid(In_Valid),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .Out_Valid(V39_Valid), .Out_Error(V39_Error),
        .Quotient(V39_Q), .Remainder(V39_R)
    );
    divider_v43sj17 u_v43 (
        .Clk(Clk), .Reset_N(Reset_N), .In_Valid(In_Valid),
        .Dividend_Hi(Dividend_Hi), .Divisor(Divisor),
        .Out_Valid(V43_Valid), .Out_Error(V43_Error),
        .Quotient(V43_Q), .Remainder(V43_R)
    );

    always #5 Clk = ~Clk;

    function automatic [63:0] random64;
        begin
            random64 = {$urandom, $urandom};
        end
    endfunction

    task automatic add_vector;
        input [63:0] X;
        input [63:0] D;
        reg [127:0] Wide_Numerator;
        reg [127:0] Wide_Quotient;
        begin
            if (!D[63] || X >= D || Vector_Count >= MAX_VECTORS)
                $fatal(1, "invalid equivalence vector X=%016x D=%016x", X, D);
            Wide_Numerator = {X, 64'b0};
            Wide_Quotient = Wide_Numerator / D;
            Vector_X[Vector_Count] = X;
            Vector_D[Vector_Count] = D;
            Expected_Q[Vector_Count] = Wide_Quotient[63:0];
            Expected_R[Vector_Count] = Wide_Numerator % D;
            Vector_Count = Vector_Count + 1;
        end
    endtask

    task automatic check_output;
        input integer Expected_Index;
        begin
            if ({V36_Valid, V39_Valid, V43_Valid} !== 3'b111 ||
                {V36_Error, V39_Error, V43_Error} !== 3'b000 ||
                V36_Q !== V39_Q || V36_Q !== V43_Q ||
                V36_R !== V39_R || V36_R !== V43_R ||
                V36_Q !== Expected_Q[Expected_Index] ||
                V36_R !== Expected_R[Expected_Index]) begin
                $display("EQUIVALENCE FAIL index=%0d X=%016x D=%016x", Expected_Index,
                         Vector_X[Expected_Index], Vector_D[Expected_Index]);
                $display("V36 valid/error/q/r=%b/%b/%016x/%016x", V36_Valid, V36_Error, V36_Q, V36_R);
                $display("V39 valid/error/q/r=%b/%b/%016x/%016x", V39_Valid, V39_Error, V39_Q, V39_R);
                $display("V43 valid/error/q/r=%b/%b/%016x/%016x", V43_Valid, V43_Error, V43_Q, V43_R);
                $display("expected q/r=%016x/%016x", Expected_Q[Expected_Index], Expected_R[Expected_Index]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        Seed = 32'h364343;
        Tests = 500;
        Vector_Count = 0;
        if (!$value$plusargs("SEED=%d", Seed)) Seed = 32'h364343;
        if (!$value$plusargs("TESTS=%d", Tests)) Tests = 500;
        if (Tests < 0 || Tests > MAX_VECTORS - 16)
            $fatal(1, "invalid TESTS=%0d", Tests);
        Seed = $urandom(Seed);

        add_vector(64'd0,                64'h8000000000000000);
        add_vector(64'h7fffffffffffffff, 64'h8000000000000000);
        add_vector(64'h8000000000000000, 64'h8000000000000001);
        add_vector(64'h801fffffffffffff, 64'h8020000000000000);
        add_vector(64'h8020000000000000, 64'h8020000000000001);
        add_vector(64'h819fffffdfffffff, 64'h819fffffe0000000);
        add_vector(64'hbfffffffffffffff, 64'hc000000000000000);
        add_vector(64'hffdfffffffffffff, 64'hffe0000000000000);
        add_vector(64'hfffffffffffffffe, 64'hffffffffffffffff);

        for (Index = 0; Index < Tests; Index = Index + 1) begin
            Test_D = random64() | 64'h8000000000000000;
            Test_X = random64();
            if (Test_X >= Test_D)
                Test_X = Test_X - Test_D;
            add_vector(Test_X, Test_D);
        end

        repeat (4) @(negedge Clk);
        Reset_N = 1'b1;
        Send_Index = 0;
        Receive_Index = 0;
        Cycles = 0;
        while (Receive_Index < Vector_Count) begin
            @(negedge Clk);
            Cycles = Cycles + 1;
            if (Cycles > Vector_Count + 8)
                $fatal(1, "equivalence timeout sent=%0d received=%0d", Send_Index, Receive_Index);
            if (V36_Valid || V39_Valid || V43_Valid) begin
                check_output(Receive_Index);
                Receive_Index = Receive_Index + 1;
            end
            if (Send_Index < Vector_Count) begin
                Dividend_Hi = Vector_X[Send_Index];
                Divisor = Vector_D[Send_Index];
                In_Valid = 1'b1;
                Send_Index = Send_Index + 1;
            end else begin
                In_Valid = 1'b0;
            end
        end
        @(negedge Clk);
        In_Valid = 1'b0;
        $display("PASS V36/V39/V43 exact back-to-back equivalence vectors=%0d", Vector_Count);
        $finish;
    end
endmodule

`default_nettype wire
