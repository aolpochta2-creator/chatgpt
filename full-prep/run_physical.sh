#!/usr/bin/env bash
set -euo pipefail

: "${VARIANT:?VARIANT is required}"
: "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
: "${SOURCE_RUN_ID:?SOURCE_RUN_ID is required}"
: "${ORFS_IMAGE:?ORFS_IMAGE is required}"
if [[ "$VARIANT" != 36 && "$VARIANT" != 43 ]]; then
    echo "VARIANT must be 36 or 43" >&2
    exit 1
fi

cd /work
set -a
source full-prep/contract.env
set +a
if [[ "$FLOORPLAN_STATUS" != frozen || -z "$DIE_AREA" || -z "$CORE_AREA" ]]; then
    echo "canonical physical launch requires a frozen common floorplan" >&2
    exit 1
fi
[[ "$CLOCK_PERIOD" == 15.0 ]]
[[ "$PHYSICAL_SEED" == 1 ]]
[[ "$DRT_OR_K" == 1.0 ]]

source /OpenROAD-flow-scripts/env.sh
export LIBERTY=/work/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
export OPENROAD_EXE=/OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad
export YOSYS_EXE=/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys
export FULL_PREP_COMMON_NETLIST=/work/full-prep-common-out/common_predictor.mapped.v
export FULL_PREP_VARIANT_NETLIST=/work/full-prep-out/v${VARIANT}/variant_only.mapped.v
export FULL_PREP_PHYSICAL_NETLIST=/work/full-prep-out/v${VARIANT}/full_prep_v44.physical_input.v
export FULL_PREP_DIE_AREA="$DIE_AREA"
export FULL_PREP_CORE_AREA="$CORE_AREA"
export FULL_PREP_PLACE_DENSITY="$PLACE_DENSITY"
export CLOCK_PERIOD PHYSICAL_SEED DRT_OR_K PLACE_DENSITY
export VARIANT SOURCE_COMMIT SOURCE_RUN_ID ORFS_IMAGE

for required in \
    "$FULL_PREP_COMMON_NETLIST" \
    "$FULL_PREP_VARIANT_NETLIST" \
    full-prep-common-out/common_manifest.json \
    "full-prep-out/v${VARIANT}/mapped_metrics.json" \
    build/coeff_rom.mem build/square_a.mem build/square_b.mem build/cube.mem; do
    test -s "$required"
done
sha256sum --check audit/production_rtl_v44_prep5.sha256
sha256sum --check audit/rom_v44.sha256

mkdir -p full-prep-work/tooling
cp /OpenROAD-flow-scripts/flow/scripts/cts.tcl full-prep-work/tooling/
cp /OpenROAD-flow-scripts/flow/scripts/detail_route.tcl full-prep-work/tooling/
cp /OpenROAD-flow-scripts/flow/scripts/variables.yaml full-prep-work/tooling/
openroad_version=$("$OPENROAD_EXE" -version)
grep -q 'g84e3ff1eb2' <<<"$openroad_version"
expected_image=$(cat physical/image.txt)
[[ "$ORFS_IMAGE" == "$expected_image" ]]
test "$(sha256sum /OpenROAD-flow-scripts/flow/Makefile | cut -d' ' -f1)" = \
    036a76c4b673214f346491ff548d7bd2af2ab74de0351975197d22f081ea3216
test "$(sha256sum full-prep-work/tooling/detail_route.tcl | cut -d' ' -f1)" = \
    e4041889c5949b6ea62f6e0605588c8bcdc55ea62bf9b71c51474bfd5d560952
find platforms/nangate45 -type f -print0 | LC_ALL=C sort -z \
    | xargs -0 sha256sum > full-prep-work/tooling/nangate45-platform-files.sha256

{
    printf '%s\n' "$openroad_version"
    "$YOSYS_EXE" -V
    printf 'ORFS_IMAGE=%s\n' "$ORFS_IMAGE"
    printf '%s\n' 'ORFS_PLATFORM_COMMIT=0c914a7471340da86058dfe4d25d537f0282a508'
    printf '%s\n' 'OPENROAD_IMAGE_SOURCE_COMMIT=84e3ff1eb2c36302cef42e4f70a69efe4cfbb126'
    printf 'CLOCK_PERIOD_NS=%s\n' "$CLOCK_PERIOD"
    printf 'VARIANT=%s\n' "$VARIANT"
    printf 'PHYSICAL_SEED=%s\n' "$PHYSICAL_SEED"
    printf 'DRT_OR_K=%s\n' "$DRT_OR_K"
    printf 'DIE_AREA=%s\n' "$DIE_AREA"
    printf 'CORE_AREA=%s\n' "$CORE_AREA"
    printf 'PLACE_DENSITY=%s\n' "$PLACE_DENSITY"
    printf 'SOURCE_COMMIT=%s\n' "$SOURCE_COMMIT"
    printf 'SOURCE_RUN_ID=%s\n' "$SOURCE_RUN_ID"
    printf '%s\n' 'MAPPED_SOURCE=same-commit same-workflow full-PREP mapping job'
    sha256sum /OpenROAD-flow-scripts/flow/Makefile
    sha256sum full-prep-work/tooling/detail_route.tcl
    sha256sum full-prep-work/tooling/nangate45-platform-files.sha256
    sha256sum full-prep-toolchain/source-lock.txt
    sha256sum "$LIBERTY" "$FULL_PREP_COMMON_NETLIST" \
        "$FULL_PREP_VARIANT_NETLIST" full-prep-common-out/common_manifest.json
    sha256sum platforms/nangate45/lef/NangateOpenCellLibrary.tech.lef \
        platforms/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef
    sha256sum build/coeff_rom.mem build/square_a.mem build/square_b.mem build/cube.mem
    sha256sum full-prep/full_prep_top.sv full-prep/contract.env full-prep/config.mk \
        full-prep/constraints.sdc
} > full-prep-work/toolchain.txt

python3 - <<'PY'
import math
import os
import re
from pathlib import Path

liberty = Path(os.environ['LIBERTY']).read_text()
assert re.search(r'time_unit\s*:\s*"1ns"', liberty)
assert re.search(r'capacitive_load_unit\s*\(\s*1\s*,\s*ff\s*\)', liberty)
period = float(os.environ['CLOCK_PERIOD'])
assert math.isclose(period, 15.0, abs_tol=1e-12)
assert int(os.environ['PHYSICAL_SEED']) == 1
assert math.isclose(float(os.environ['DRT_OR_K']), 1.0, abs_tol=1e-12)
print('verified full-PREP Liberty units, period, seed and effective DRT K')
PY

"$OPENROAD_EXE" -exit full-prep/baseline.tcl 2>&1 \
    | tee full-prep-work/mapped_baseline.rpt
grep -q 'FULL_PREP_BASELINE_COMPLETE' full-prep-work/mapped_baseline.rpt
if grep -Eq '^(Error:|Error |\[ERROR)' full-prep-work/mapped_baseline.rpt; then
    exit 1
fi

# Materialize only constants as tie cells.  The archived mapped logic is not
# resynthesized or remapped before physical implementation.
"$YOSYS_EXE" -Q -p "
    read_liberty -lib $LIBERTY;
    read_verilog $FULL_PREP_COMMON_NETLIST;
    read_verilog $FULL_PREP_VARIANT_NETLIST;
    hierarchy -check -top full_prep_v44;
    flatten;
    hilomap -hicell LOGIC1_X1 Z -locell LOGIC0_X1 Z;
    write_verilog -noattr -noexpr $FULL_PREP_PHYSICAL_NETLIST;
" > full-prep-work/tie_materialization.log
test -s "$FULL_PREP_PHYSICAL_NETLIST"

flow_start_epoch=$(date +%s)
make -C /OpenROAD-flow-scripts/flow \
    DESIGN_CONFIG=/work/full-prep/config.mk \
    WORK_HOME=/work/full-prep-work \
    finish 2>&1 | tee full-prep-work/flow.log
if grep -Eq '^(Error:|Error |\[ERROR)' full-prep-work/flow.log; then
    exit 1
fi
grep -q 'FULL_PREP_PHYSICAL_CHECKPOINT_COMPLETE' full-prep-work/flow.log
flow_end_epoch=$(date +%s)
export FLOW_RUNTIME_SECONDS=$((flow_end_epoch - flow_start_epoch))
python3 full-prep/validate_physical.py full-prep-work
