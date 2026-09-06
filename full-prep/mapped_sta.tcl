set top full_prep_v44
set liberty $::env(LIBERTY)
set common_netlist $::env(COMMON_NETLIST)
set variant_netlist $::env(VARIANT_NETLIST)
set platform_dir /OpenROAD-flow-scripts/flow/platforms/nangate45

foreach lef [list \
        $platform_dir/lef/NangateOpenCellLibrary.tech.lef \
        $platform_dir/lef/NangateOpenCellLibrary.macro.mod.lef] {
    if {![file exists $lef] || [file size $lef] == 0} {
        error "Missing pinned Nangate45 LEF: $lef"
    }
    read_lef $lef
}
read_liberty $liberty
read_verilog $common_netlist
read_verilog $variant_netlist
link_design $top
source /work/full-prep/constraints.sdc
report_units

report_checks -path_delay max -format full_clock_expanded \
    -group_path_count 20 -endpoint_path_count 1 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -max -digits 4
report_check_types -max_slew -max_capacitance -max_fanout \
    -violators -digits 4
puts "FULL_PREP_MAPPED_STA_COMPLETE"
