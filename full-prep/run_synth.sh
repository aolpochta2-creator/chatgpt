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
    printf '%s\n' 'MAPPING_MODE=yosys-abc-hierarchical-default'
    printf '%s\n' "MAPPING_INVOCATION=abc -liberty <pinned Nangate45 Liberty> -D $ABC_DELAY_PS"
    printf '%s\n' 'RATIONALE=default flat ABC timed out while abc-fast produced diagnostic low-QoR high-fanout X1 mapping'
    printf '%s\n' 'NETWORK_POLICY=preserve production RTL module boundaries through default ABC; flatten only after mapping'
    printf '%s\n' 'ROM_POLICY=explicit generated ROM logic mapped as its own real module; no black box, oracle or area-free source'
} > "$out/mapping-contract.txt"

rtl_files=$(find rtl -maxdepth 1 -name '*.sv' -print | sort | tr '\n' ' ')
/usr/bin/time -v -o "$out/yosys-time.txt" \
yosys -Q -l "$out/yosys.log" -p "
    read_verilog -sv $rtl_files build/hz_reducers_generated.sv full-prep/full_prep_top.sv;
    chparam -set VARIANT $variant full_prep_v44;
    hierarchy -check -top full_prep_v44;
    synth -top full_prep_v44 -noabc;
    tee -o $out/premap.stat.rpt stat;
    write_json $out/premap.json;
    dfflibmap -liberty $LIBERTY;
    abc -liberty $LIBERTY -D $ABC_DELAY_PS;
    clean;
    tee -o $out/mapped.hier.stat.rpt stat -liberty $LIBERTY;
    write_json $out/mapped.hier.json;
    flatten;
    clean -purge;
    read_liberty -lib $LIBERTY;
    hierarchy -check -top full_prep_v44;
    check -assert;
    tee -o $out/stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec $out/full_prep_v44.mapped.v;
    write_json $out/full_prep_v44.mapped.json;
"

abc_networks=$(grep -c 'Extracting gate netlist of module' "$out/yosys.log")
if (( abc_networks < 4 )); then
    echo "expected multiple hierarchy-bounded ABC networks, got $abc_networks" >&2
    exit 1
fi
grep -Fq 'ABC: + scorr' "$out/yosys.log"
grep -Fq 'ABC: + dc2' "$out/yosys.log"
grep -Fq 'ABC: + &nf' "$out/yosys.log"
if grep -Fq 'ABC: + map -D' "$out/yosys.log"; then
    echo "unexpected abc -fast script detected" >&2
    exit 1
fi
printf 'ABC_MAPPED_NETWORKS=%s\n' "$abc_networks" \
    | tee -a "$out/mapping-contract.txt"

for evidence in \
    "$out/yosys.log" \
    "$out/yosys-time.txt" \
    "$out/premap.stat.rpt" \
    "$out/premap.json" \
    "$out/mapped.hier.stat.rpt" \
    "$out/mapped.hier.json" \
    "$out/mapping-contract.txt" \
    "$out/stat.rpt" \
    "$out/full_prep_v44.mapped.v" \
    "$out/full_prep_v44.mapped.json"; do
    test -s "$evidence"
done
grep -Eq 'Number of memories:[[:space:]]+0' "$out/premap.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/mapped.hier.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/stat.rpt"
if grep -Eq 'Number of memories:[[:space:]]+[1-9]' \
    "$out/premap.stat.rpt" "$out/mapped.hier.stat.rpt" "$out/stat.rpt"; then
    echo "residual mapped memory detected" >&2
    exit 1
fi
sha256sum --check audit/production_rtl_v44_prep5.sha256
