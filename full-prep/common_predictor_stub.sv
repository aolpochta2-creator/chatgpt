`default_nettype none

// Experiment-only interface declaration used while mapping the variant side
// of the full-PREP A/B.  The implementation is supplied later by the single
// frozen common-mapping artifact.  This file never replaces production RTL.
(* blackbox *)
module hz_predictor_csa (
    input  wire [63:0] Divisor,
    output wire [79:0] Pred_S,
    output wire [79:0] Pred_C,
    output wire signed [7:0] Pred_Wrap,
    output wire Carry_Low,
    output wire Is_Power_Boundary
);
endmodule

`default_nettype wire
