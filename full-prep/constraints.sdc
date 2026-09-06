if {![info exists ::env(CLOCK_PERIOD)]} {
    error "CLOCK_PERIOD is required for the full-PREP contract"
}
set clock_period $::env(CLOCK_PERIOD)
if {![string is double -strict $clock_period] || $clock_period <= 0.0} {
    error "CLOCK_PERIOD must be a positive number, got '$clock_period'"
}
puts "FULL_PREP_CLOCK_PERIOD_NS $clock_period"
create_clock -name Core_Clk -period $clock_period [get_ports Clk]
set_false_path -from [get_ports Reset_N]
set_input_delay 0.0 -clock Core_Clk [get_ports {Dividend_Hi Divisor}]
set_input_transition 0.05 [get_ports {Dividend_Hi Divisor}]
set_output_delay 0.0 -clock Core_Clk \
    [get_ports {NX Reciprocal_Remainder}]
set_load 5.0 [get_ports {NX Reciprocal_Remainder}]
set_max_fanout 20 [current_design]
set_max_transition 0.20 [current_design]
