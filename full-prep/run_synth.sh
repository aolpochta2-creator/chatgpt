#!/usr/bin/env bash
set -euo pipefail

variant="${1:?usage: run_synth.sh <36|43>}"
if [[ "$variant" != 36 && "$variant" != 43 ]]; then
    echo "variant must be 36 or 43" >&2
    exit 1
fi
: "${LIBERTY:?LIBERTY is required}"
: "${CLOCK_PERIOD:?CLOCK_PERIOD is required}"
: "${ABC_DELAY_PS:?ABC_DELAY_PS is required}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
cd "$repo_root"
out="full-prep-out/v${variant}"
mkdir -p build "$out"

python3 - "$CLOCK_PERIOD" "$ABC_DELAY_PS" <<'PY'
import math
import sys
period = float(sys.argv[1])
delay = int(sys.argv[2])
assert math.isfinite(period) and period > 0
assert delay == round(period * 1000), (period, delay)
PY

sha256sum --check audit/production_rtl_v44_prep5.sha256 \
    | tee "$out/production-rtl-lock.txt"
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
sha256sum --check audit/rom_v44.sha256
sha256sum build/coeff_rom.mem build/square_a.mem build/square_b.mem \
    build/cube.mem | tee "$out/rom-sha256.txt"
sha256sum build/hz_reducers_generated.sv full-prep/full_prep_top.sv \
    | tee "$out/generated-and-wrapper-sha256.txt"

{
    printf '%s\n' 'MAPPING_MODE=yosys-abc-fast'
    printf '%s\n' "MAPPING_INVOCATION=abc -fast -liberty <pinned Nangate45 Liberty> -D $ABC_DELAY_PS"
    printf '%s\n' 'RATIONALE=default global ABC timed out symmetrically in diagnostic run 34016766940'
    printf '%s\n' 'NETWORK_POLICY=one flat full-PREP combinational network; no ROM black boxes or hierarchy cuts'
} > "$out/mapping-contract.txt"

rtl_files=$(find rtl -maxdepth 1 -name '*.sv' -print | sort | tr '\n' ' ')
yosys -Q -l "$out/yosys.log" -p "
    read_verilog -sv $rtl_files build/hz_reducers_generated.sv full-prep/full_prep_top.sv;
    chparam -set VARIANT $variant full_prep_v44;
    hierarchy -check -top full_prep_v44;
    synth -top full_prep_v44 -flatten -noabc;
    tee -o $out/premap.stat.rpt stat;
    write_json $out/premap.json;
    dfflibmap -liberty $LIBERTY;
    abc -fast -liberty $LIBERTY -D $ABC_DELAY_PS;
    clean -purge;
    read_liberty -lib $LIBERTY;
    hierarchy -check -top full_prep_v44;
    check -assert;
    tee -o $out/stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec $out/full_prep_v44.mapped.v;
    write_json $out/full_prep_v44.mapped.json;
"

for evidence in \
    "$out/yosys.log" \
    "$out/premap.stat.rpt" \
    "$out/premap.json" \
    "$out/mapping-contract.txt" \
    "$out/stat.rpt" \
    "$out/full_prep_v44.mapped.v" \
    "$out/full_prep_v44.mapped.json"; do
    test -s "$evidence"
done
grep -Eq 'Number of memories:[[:space:]]+0' "$out/premap.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/stat.rpt"
sha256sum --check audit/production_rtl_v44_prep5.sha256
