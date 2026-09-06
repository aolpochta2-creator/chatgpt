read_lef /work/platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef
read_lef /work/platforms/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef
read_liberty $::env(LIBERTY)
read_verilog $::env(FULL_PREP_COMMON_NETLIST)
read_verilog $::env(FULL_PREP_VARIANT_NETLIST)
link_design full_prep_v44
source /work/full-prep/constraints.sdc
report_units
report_design_area
report_checks -path_delay max -group_path_count 10 -endpoint_path_count 1 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_check_types -max_slew -max_capacitance -max_fanout -violators -digits 4
puts "FULL_PREP_BASELINE_COMPLETE"
