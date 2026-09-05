# Physical audit of paired, already mapped V44 kernel netlists.
export DESIGN_NAME = $(TOP)
export PLATFORM = nangate45
export PLATFORM_DIR = /work/platforms/nangate45
export VERILOG_FILES = /work/build/$(TOP).physical_input.v
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = /work/physical/constraints.sdc

# Identical absolute floorplan; do not give either control different room.
export DIE_AREA = 0 0 520 520
export CORE_AREA = 10 10 510 510
export PLACE_DENSITY = 0.45
export NUM_CORES = 2
export TNS_END_PERCENT = 100
export POST_FINAL_REPORT_TCL = /work/physical/report.tcl
export PRE_CTS_TCL = /work/physical/trace_exec.tcl

# Paired causality experiment: every PREP6/PREP5 pair uses the same explicit
# seed.  Seed 1 is the primary matrix; seed 2 is reserved for the conditional
# V43@3.15 scatter check.  No seed is selected opportunistically.
export GPL_RANDOM_SEED = $(PHYSICAL_SEED)
export GRT_SEED = $(PHYSICAL_SEED)
export OR_SEED = $(PHYSICAL_SEED)

# Keep post-CTS repair_timing enabled.  The previous SIGILL was localized to
# the subsequent kepler-formal LEC helper in the pinned official ORFS image,
# not to OpenROAD repair_timing itself.  Kepler/naja contains AVX-512 code that
# is not portable to the GitHub Actions runner; LEC_CHECK=0 skips only that
# developer-oriented equivalence check while CTS, repair_timing, routing,
# OpenRCX extraction and final STA remain enabled.
export SKIP_CTS_REPAIR_TIMING = 0
export LEC_CHECK = 0

# Power/IR analysis needs activity and a supply model outside this experiment.
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
