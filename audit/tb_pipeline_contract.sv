`timescale 1ns/1ps
`default_nettype none

module tb_pipeline_contract;
    reg Clk = 1'b0;
    reg Reset_N = 1'b0;
    reg In_Valid = 1'b0;
    reg [63:0] Dividend_Hi = 64'd0;
    reg [63:0] Divisor = 64'h8000000000000000;

    wire V36_Valid, V39_Valid, V43_Valid;
    wire V36_Error, V39_Error, V43_Error;
    wire [63:0] V36_Q, V39_Q, V43_Q;
    wire [63:0] V36_R, V39_R, V43_R;

    reg Prev_Valid;
    reg Prev_Error;
    reg [63:0] Prev_Q;
    reg [63:0] Prev_R;
    integer Prev_Tag;
    integer Edge_Count;

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

    task automatic fail;
        input [8*112-1:0] Message;
        begin
            $display("PIPELINE FAIL edge=%0d previous-tag=%0d: %0s",
                     Edge_Count, Prev_Tag, Message);
            $fatal(1);
        end
    endtask

    task automatic check_previous_post_nba;
        begin
            if ({V36_Valid, V39_Valid, V43_Valid} !== {3{Prev_Valid}})
                fail("Out_Valid does not match the transaction accepted at the previous edge");
            if ({V36_Error, V39_Error, V43_Error} !== {3{Prev_Error}})
                fail("Out_Error does not match the previous edge, including a bubble");
            if (Prev_Valid) begin
                if (V36_Q !== V39_Q || V36_Q !== V43_Q ||
                    V36_R !== V39_R || V36_R !== V43_R)
                    fail("V36/V39/V43 output association mismatch");
                if (Prev_Error) begin
                    if (V36_Q !== 64'd0 || V36_R !== 64'd0)
                        fail("accepted invalid transaction did not return q=r=0");
                end else if (V36_Q !== Prev_Q || V36_R !== Prev_R) begin
                    $display("got q/r=%016x/%016x expected=%016x/%016x",
                             V36_Q, V36_R, Prev_Q, Prev_R);
                    fail("legal transaction result mismatch");
                end
            end
        end
    endtask

    task automatic run_cycle;
        input This_Valid;
        input [63:0] This_X;
        input [63:0] This_D;
        input integer Expected_Prep_Correction;
        input integer Expected_Final_Correction;
        input integer Expected_M;
        input integer This_Tag;
        reg This_Error;
        reg [127:0] Wide_Numerator;
        reg [127:0] Wide_Quotient;
        begin
            @(negedge Clk);
            In_Valid = This_Valid;
            Dividend_Hi = This_X;
            Divisor = This_D;
            #1;

            This_Error = !This_D[63] || (This_X >= This_D);
            if (This_Valid && !This_Error && Expected_Prep_Correction >= 0) begin
                if (u_v36.u_core.u_prep.Correction !== Expected_Prep_Correction ||
                    u_v39.u_core.u_prep.Correction !== Expected_Prep_Correction ||
                    u_v43.u_core.u_prep.Correction !== Expected_Prep_Correction)
                    fail("compiled PREP correction mismatch");
            end
            if (Expected_M >= 0) begin
                if (u_v36.u_core.u_prep.u_predictor.M !== Expected_M ||
                    u_v39.u_core.u_prep.u_predictor.M !== Expected_M ||
                    u_v43.u_core.u_prep.u_predictor.M !== Expected_M)
                    fail("compiled predictor M bucket-edge mismatch");
            end

            @(posedge Clk);
            #1; // Explicit post-NBA observation point for edge E_t.
            Edge_Count = Edge_Count + 1;
            check_previous_post_nba();

            // The current input has just entered Stage1. Its FINAL cone is now
            // visible, but its registered output is required only at E_(t+1).
            if (This_Valid && !This_Error && Expected_Final_Correction >= 0) begin
                if (u_v36.u_core.u_final.Correction !== Expected_Final_Correction ||
                    u_v39.u_core.u_final.Correction !== Expected_Final_Correction ||
                    u_v43.u_core.u_final.Correction !== Expected_Final_Correction)
                    fail("compiled FINAL correction mismatch");
            end

            Prev_Valid = This_Valid;
            Prev_Error = This_Error;
            Prev_Tag = This_Tag;
            if (This_Valid && !This_Error) begin
                Wide_Numerator = {This_X, 64'b0};
                Wide_Quotient = Wide_Numerator / This_D;
                Prev_Q = Wide_Quotient[63:0];
                Prev_R = Wide_Numerator % This_D;
            end else begin
                Prev_Q = 64'd0;
                Prev_R = 64'd0;
            end
        end
    endtask

    task automatic reset_flush_pending;
        begin
            @(negedge Clk);
            In_Valid = 1'b0;
            Reset_N = 1'b0;
            #1;
            if ({V36_Valid, V39_Valid, V43_Valid} !== 3'b000 ||
                {V36_Error, V39_Error, V43_Error} !== 3'b000 ||
                V36_Q !== 64'd0 || V39_Q !== 64'd0 || V43_Q !== 64'd0 ||
                V36_R !== 64'd0 || V39_R !== 64'd0 || V43_R !== 64'd0)
                fail("asynchronous reset did not clear/flush all outputs");
            @(posedge Clk);
            #1;
            if ({V36_Valid, V39_Valid, V43_Valid} !== 3'b000)
                fail("pending transaction survived reset");
            Prev_Valid = 1'b0;
            Prev_Error = 1'b0;
            Prev_Q = 64'd0;
            Prev_R = 64'd0;
            Prev_Tag = 0;
            @(negedge Clk);
            Reset_N = 1'b1;
        end
    endtask

    initial begin
        Prev_Valid = 1'b0;
        Prev_Error = 1'b0;
        Prev_Q = 64'd0;
        Prev_R = 64'd0;
        Prev_Tag = 0;
        Edge_Count = 0;

        repeat (3) @(posedge Clk);
        #1;
        if ({V36_Valid, V39_Valid, V43_Valid} !== 3'b000)
            fail("reset startup valid state");
        @(negedge Clk);
        Reset_N = 1'b1;

        // Legal A/B are intentionally back-to-back. The first five entries
        // cover every exact PREP correction with the required endpoint
        // witnesses at correction 0 and correction 4.
        run_cycle(1, 64'h819fffffdfffffff, 64'h819fffffe0000000, 0, -1, -1, 10);
        run_cycle(1, 64'h801ffffffffffffe, 64'h801fffffffffffff, 1, -1, -1, 11);
        run_cycle(1, 64'h90056413cf6391c3, 64'h90056413cf6391c4, 2, -1, -1, 12);
        run_cycle(1, 64'h8000000000000000, 64'h8000000000000001, 3, -1, -1, 13);
        run_cycle(1, 64'h8020000000000000, 64'h8020000000000001, 4, -1, -1, 14);

        // Final predictor bucket edge into m=2048 and the maximum divisor.
        run_cycle(1, 64'hffdfffffffffffff, 64'hffe0000000000000, 1, -1, 2047, 20);
        run_cycle(1, 64'hffe0000000000000, 64'hffe0000000000001, 1, -1, 2048, 21);
        run_cycle(1, 64'hfffffffffffffffe, 64'hffffffffffffffff, 1, -1, 2048, 22);

        // Required current-FINAL correction=3 witness.
        run_cycle(1, 64'he4a3acb2922b34f4, 64'heb5fe00000000001, 1, 3, -1, 30);

        // Exact power boundary covers X=0, X=D-1 and R=0.
        run_cycle(1, 64'd0,                64'h8000000000000000, -1, -1, -1, 40);
        run_cycle(1, 64'h7fffffffffffffff, 64'h8000000000000000, -1, -1, -1, 41);

        // Bubble carries an error value in the present RTL. This explicitly
        // avoids the false assumption Out_Valid=0 -> Out_Error=0.
        run_cycle(0, 64'd0, 64'h7fffffffffffffff, -1, -1, -1, 50);
        run_cycle(1, 64'd0, 64'h7fffffffffffffff, -1, -1, -1, 51); // invalid D
        run_cycle(1, 64'd0, 64'hffffffffffffffff, 1, -1, 2048, 52); // legal
        run_cycle(1, 64'h8000000000000001, 64'h8000000000000001, -1, -1, -1, 53); // X>=D
        run_cycle(1, 64'h123456789abcdef0, 64'hf123456789abcdef, -1, -1, -1, 54); // legal C
        run_cycle(0, 64'd0, 64'h8000000000000000, -1, -1, -1, 55);
        run_cycle(0, 64'd0, 64'h8000000000000000, -1, -1, -1, 56);

        // Accept a legal transaction, then assert reset before its output edge.
        run_cycle(1, 64'h0123456789abcdef, 64'hc123456789abcdef, -1, -1, -1, 60);
        reset_flush_pending();

        // First post-reset transaction and its following output edge.
        run_cycle(1, 64'd0, 64'h8000000000000000, -1, -1, -1, 70);
        run_cycle(0, 64'd0, 64'h8000000000000000, -1, -1, -1, 71);
        run_cycle(0, 64'd0, 64'h8000000000000000, -1, -1, -1, 72);

        $display("PASS post-NBA pipeline contract edges=%0d: legal/back-to-back/bubble/invalid/reset association", Edge_Count);
        $finish;
    end
endmodule

`default_nettype wire
