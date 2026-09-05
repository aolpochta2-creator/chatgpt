read_lef /work/platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef
read_lef /work/platforms/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef
read_liberty $::env(LIBERTY)
read_verilog /work/build/$::env(TOP).mapped.v
link_design $::env(TOP)
read_sdc /work/physical/constraints.sdc
report_units
report_checks -path_delay max -group_path_count 5 -endpoint_path_count 1 \
    -fields {slew capacitance input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_check_types -max_slew -max_capacitance -max_fanout -violators -digits 4
