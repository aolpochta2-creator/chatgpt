set top $::env(TOP)
set liberty $::env(LIBERTY)
read_liberty $liberty
read_verilog build/${top}.mapped.v
link_design $top

create_clock -name Core_Clk -period 10.0 [get_ports Clk]
set non_clock_inputs [remove_from_collection [all_inputs] [get_ports Clk]]
set_input_delay 0.0 -clock Core_Clk $non_clock_inputs
set_output_delay 0.0 -clock Core_Clk [all_outputs]
set_load 0.005 [all_outputs]

report_checks -path_delay max -group_count 10 -endpoint_count 10 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -digits 4
