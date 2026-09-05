# Full two-stage divider control run.  Units match Nangate45: ns and fF.
create_clock -name Core_Clk -period 10.0 [get_ports Clk]
set_false_path -from [get_ports Reset_N]
set_input_delay 0.0 -clock Core_Clk \
    [get_ports {In_Valid Dividend_Hi Divisor}]
set_input_transition 0.05 [get_ports {In_Valid Dividend_Hi Divisor}]
set_output_delay 0.0 -clock Core_Clk \
    [get_ports {Out_Valid Out_Error Quotient Remainder}]
set_load 5.0 [get_ports {Out_Valid Out_Error Quotient Remainder}]
set_max_fanout 20 [current_design]
set_max_transition 0.20 [current_design]
