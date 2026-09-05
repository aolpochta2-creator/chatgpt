# Validated by run.sh: Nangate45 uses ns and fF.  5 fF = 0.005 pF.
# CLOCK_PERIOD is the only swept implementation constraint; all other physical
# inputs stay fixed.  Keep 10 ns as the explicit non-sweep/manual default.
if {[info exists ::env(CLOCK_PERIOD)]} {
    set clock_period $::env(CLOCK_PERIOD)
} else {
    set clock_period 10.0
}
if {![string is double -strict $clock_period] || $clock_period <= 0.0} {
    error "CLOCK_PERIOD must be a positive number, got '$clock_period'"
}
puts "PHYSICAL_CLOCK_PERIOD_NS $clock_period"
create_clock -name Core_Clk -period $clock_period [get_ports Clk]
set_false_path -from [get_ports Reset_N]
set_input_delay 0.0 -clock Core_Clk \
    [get_ports {Pred_S Pred_C Pred_Wrap Carry_Low Candidate_K X D}]
set_input_transition 0.05 \
    [get_ports {Pred_S Pred_C Pred_Wrap Carry_Low Candidate_K X D}]
set_output_delay 0.0 -clock Core_Clk [get_ports {Residual_Path NX_Path}]
set_load 5.0 [get_ports {Residual_Path NX_Path}]
set_max_fanout 20 [current_design]
set_max_transition 0.20 [current_design]
