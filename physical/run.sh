#!/usr/bin/env bash
set -euo pipefail
: "${TOP:?TOP is required}"
: "${CLOCK_PERIOD:=10.0}"
: "${PREP_MODE:?PREP_MODE is required}"
: "${PHYSICAL_SEED:?PHYSICAL_SEED is required}"
: "${EXPERIMENT_LABEL:?EXPERIMENT_LABEL is required}"
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${SOURCE_RUN_ID:?SOURCE_RUN_ID is required}"
export CLOCK_PERIOD PREP_MODE PHYSICAL_SEED EXPERIMENT_LABEL SOURCE_COMMIT SOURCE_RUN_ID
cd /work
source /OpenROAD-flow-scripts/env.sh
export LIBERTY=/work/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
export OPENROAD_EXE=/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad
export YOSYS_EXE=/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys
mkdir -p physical-work
mkdir -p physical-work/tooling
cp /OpenROAD-flow-scripts/flow/scripts/cts.tcl physical-work/tooling/
cp /OpenROAD-flow-scripts/flow/scripts/variables.yaml physical-work/tooling/
{
    "$OPENROAD_EXE" -version
    "$YOSYS_EXE" -V
    printf 'ORFS_IMAGE=%s\n' "$ORFS_IMAGE"
    printf 'CLOCK_PERIOD_NS=%s\n' "$CLOCK_PERIOD"
    printf 'PREP_MODE=%s\n' "$PREP_MODE"
    printf 'PHYSICAL_SEED=%s\n' "$PHYSICAL_SEED"
    printf 'EXPERIMENT_LABEL=%s\n' "$EXPERIMENT_LABEL"
    printf 'SOURCE_COMMIT=%s\n' "$SOURCE_COMMIT"
    printf 'SOURCE_RUN_ID=%s\n' "$SOURCE_RUN_ID"
    printf '%s\n' 'MAPPED_SOURCE=same-commit same-workflow paired mapping job'
    sha256sum /OpenROAD-flow-scripts/flow/Makefile
    sha256sum "$LIBERTY" "build/${TOP}.mapped.v" build/paired_mapping_toolchain.txt
    printf '%s\n' '--- paired mapping toolchain ---'
    sed -n '1,120p' build/paired_mapping_toolchain.txt
} > physical-work/toolchain.txt
python3 - <<'PY'
import math,os,re
from pathlib import Path
s=Path(os.environ['LIBERTY']).read_text()
assert re.search(r'time_unit\s*:\s*"1ns"',s), 'Expected ns'
assert re.search(r'capacitive_load_unit\s*\(\s*1\s*,\s*ff\s*\)',s), 'Expected fF'
period=float(os.environ['CLOCK_PERIOD'])
assert math.isfinite(period) and 0.1 <= period <= 1000.0, 'Invalid CLOCK_PERIOD'
seed=int(os.environ['PHYSICAL_SEED'])
assert 1 <= seed <= 2147483647, 'Invalid PHYSICAL_SEED'
assert os.environ['PREP_MODE'] in {'prep5', 'prep6'}, 'Invalid PREP_MODE'
print(f'Verified Liberty units: ns and fF; output load is 5 fF; clock period is {period:g} ns; seed={seed}')
PY
"$OPENROAD_EXE" -exit physical/baseline.tcl 2>&1 | tee physical-work/mapped_corrected.rpt
if grep -Eq '^(Error:|Error |\[ERROR)' physical-work/mapped_corrected.rpt; then exit 1; fi

# Only materialize constants as tie cells.  There is no re-synthesis or ABC
# remapping: physical implementation starts from the archived mapped logic.
"$YOSYS_EXE" -Q -p "
    read_liberty -lib $LIBERTY;
    read_verilog build/${TOP}.mapped.v;
    hierarchy -check -top $TOP;
    hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z;
    write_verilog -noattr -noexpr build/${TOP}.physical_input.v;
" > physical-work/tie_materialization.log
flow_start_epoch=$(date +%s)
make -C /OpenROAD-flow-scripts/flow \
    DESIGN_CONFIG=/work/physical/config.mk \
    WORK_HOME=/work/physical-work \
    finish 2>&1 | tee physical-work/flow.log
if grep -Eq '^(Error:|Error |\[ERROR)' physical-work/flow.log; then exit 1; fi
grep -q 'PHYSICAL_CHECKPOINT_COMPLETE' physical-work/flow.log
flow_end_epoch=$(date +%s)
export FLOW_RUNTIME_SECONDS=$((flow_end_epoch - flow_start_epoch))
python3 physical/validate_reports.py physical-work "$TOP" "$CLOCK_PERIOD"
