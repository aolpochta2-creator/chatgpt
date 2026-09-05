# Validated by run.sh: Nangate45 uses ns and fF.  5 fF = 0.005 pF.
create_clock -name Core_Clk -period 10.0 [get_ports Clk]
set_false_path -from [get_ports Reset_N]
set_input_delay 0.0 -clock Core_Clk \
    [get_ports {Pred_S Pred_C Pred_Wrap Carry_Low Candidate_K X D}]
set_input_transition 0.05 \
    [get_ports {Pred_S Pred_C Pred_Wrap Carry_Low Candidate_K X D}]
set_output_delay 0.0 -clock Core_Clk [get_ports {Residual_Path NX_Path}]
set_load 5.0 [get_ports {Residual_Path NX_Path}]
set_max_fanout 20 [current_design]
set_max_transition 0.20 [current_design]

