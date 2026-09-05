# Called by ORFS after routed OpenRCX SPEF has been written and read into STA.
set spef $::env(RESULTS_DIR)/6_final.spef
if {![file exists $spef] || [file size $spef] == 0} {
    error "Physical checkpoint requires nonempty routed SPEF"
}
report_units
set units_file [open $::env(REPORTS_DIR)/physical_units.rpt w]
puts $units_file "OpenROAD report_units is recorded in flow.log."
puts $units_file "Liberty units asserted by physical/run.sh: time=1ns capacitance=1fF."
close $units_file
report_checks -path_delay max -format full_clock_expanded \
    -group_path_count 10 -endpoint_path_count 1 \
    -fields {slew capacitance input_pin net fanout} -digits 4 \
    > $::env(REPORTS_DIR)/physical_setup.rpt
report_checks -path_delay min -format full_clock_expanded \
    -group_path_count 5 -endpoint_path_count 1 -digits 4 \
    > $::env(REPORTS_DIR)/physical_hold.rpt
report_worst_slack -max -digits 4 > $::env(REPORTS_DIR)/physical_slack.rpt
report_worst_slack -min -digits 4 >> $::env(REPORTS_DIR)/physical_slack.rpt
report_tns -max -digits 4 >> $::env(REPORTS_DIR)/physical_slack.rpt
report_tns -min -digits 4 >> $::env(REPORTS_DIR)/physical_slack.rpt
report_check_types -max_slew -max_capacitance -max_fanout -violators -digits 4 \
    > $::env(REPORTS_DIR)/physical_electrical.rpt

set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set total_cells 0
set logical_cells 0
set flop_count 0
set logical_area 0.0
foreach inst [$block getInsts] {
    incr total_cells
    set master [$inst getMaster]
    set name [$master getName]
    if {[regexp {^(FILLCELL|TAPCELL)} $name]} {continue}
    incr logical_cells
    if {[string match "DFF*" $name]} {incr flop_count}
    set logical_area [expr {$logical_area + double([$master getWidth]) * [$master getHeight] / $dbu / $dbu}]
}
if {$flop_count != 168} {error "Expected 168 kernel DFFs, found $flop_count"}
set f [open $::env(REPORTS_DIR)/physical_counts.tsv w]
puts $f "logical_cells\t$logical_cells"
puts $f "total_cells_including_fillers\t$total_cells"
puts $f "dffs\t$flop_count"
puts $f "logical_cell_area_um2\t$logical_area"
close $f
puts "PHYSICAL_CHECKPOINT_COMPLETE SPEF=$spef DFFS=$flop_count"
