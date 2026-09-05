set top $::env(TOP)
set liberty $::env(LIBERTY)
if {[info exists ::env(NETLIST)]} {
    set netlist $::env(NETLIST)
} else {
    set netlist build/${top}.mapped.v
}
read_liberty $liberty
read_verilog $netlist
link_design $top

if {[string match "kernel_*" $top]} {
    # Shared physical assumptions; historical reports retain their original SDC.
    source physical/constraints.sdc
} elseif {[string match "divider_*" $top]} {
    source scripts/full_top_constraints.sdc
} else {
    error "No STA constraint set for top $top"
}
report_units

report_checks -path_delay max -group_path_count 10 -endpoint_path_count 10 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -digits 4
puts "STA_REPORT_COMPLETE"
