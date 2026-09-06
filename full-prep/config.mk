# V44 full-PREP PREP5 integration.  Both jobs consume the same values from
# contract.env; run_physical.sh rejects an unfrozen or incomplete floorplan.
export DESIGN_NAME = full_prep_v44
export PLATFORM = nangate45
export PLATFORM_DIR = /work/platforms/nangate45
export VERILOG_FILES = $(FULL_PREP_PHYSICAL_NETLIST)
export SYNTH_NETLIST_FILES = $(VERILOG_FILES)
export SDC_FILE = /work/full-prep/constraints.sdc

export DIE_AREA = $(FULL_PREP_DIE_AREA)
export CORE_AREA = $(FULL_PREP_CORE_AREA)
export PLACE_DENSITY := $(FULL_PREP_PLACE_DENSITY)
export NUM_CORES = 2
export TNS_END_PERCENT = 100
export POST_FINAL_REPORT_TCL = /work/full-prep/report.tcl
export PRE_CTS_TCL = /work/full-prep/trace_exec.tcl

# One predefined seed, not a sweep or best-seed search.  OR_K=1.0 makes the
# pinned DRT adjacent-swap mechanism effective; validate_physical.py checks the
# actual detailed_route command.
export GPL_RANDOM_SEED = $(PHYSICAL_SEED)
export GRT_SEED = $(PHYSICAL_SEED)
export OR_SEED = $(PHYSICAL_SEED)
export OR_K = $(DRT_OR_K)

# Timing repair remains active.  LEC_CHECK=0 skips only the documented Kepler
# AVX-512-limited developer LEC helper; post-physical equivalence stays open.
export SKIP_CTS_REPAIR_TIMING = 0
export LEC_CHECK = 0

export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
