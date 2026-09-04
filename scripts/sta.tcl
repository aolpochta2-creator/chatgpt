set top $::env(TOP)
set liberty $::env(LIBERTY)
read_liberty $liberty
read_verilog build/${top}.mapped.v
link_design $top

create_clock -name Core_Clk -period 10.0 [get_ports Clk]
set_false_path -from [get_ports Reset_N]
set_input_delay 0.0 -clock Core_Clk \
    [get_ports {Pred_S Pred_C Pred_Wrap Carry_Low Candidate_K X D}]
set_output_delay 0.0 -clock Core_Clk [get_ports {Residual_Path NX_Path}]
set_load 0.005 [get_ports {Residual_Path NX_Path}]

report_checks -path_delay max -group_path_count 10 -endpoint_path_count 10 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -digits 4
