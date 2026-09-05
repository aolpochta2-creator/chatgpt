# Physical audit of the frozen, already mapped V44 kernel netlists.
export DESIGN_NAME = $(TOP)
export PLATFORM = nangate45
export PLATFORM_DIR = /work/platforms/nangate45
export VERILOG_FILES = /work/build/$(TOP).physical_input.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = /work/physical/constraints.sdc

# Identical absolute floorplan; do not give each candidate different room.
export DIE_AREA = 0 0 520 520
export CORE_AREA = 10 10 510 510
export PLACE_DENSITY = 0.45
export NUM_CORES = 2
export TNS_END_PERCENT = 100
export POST_FINAL_REPORT_TCL = /work/physical/report.tcl
export PRE_CTS_TCL = /work/physical/trace_exec.tcl

# Diagnostic workaround for the ORFS post-CTS timing-repair helper, which
# currently exits with "child killed: illegal instruction" on the pinned
# GitHub Actions runner/toolchain. Keep CTS, routing and final extracted STA
# enabled; results from this audit must be labeled as having no post-CTS
# timing repair.
export SKIP_CTS_REPAIR_TIMING = 1

# Power/IR analysis needs activity and a supply model outside this experiment.
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
