#!/usr/bin/env bash
set -euo pipefail

: "${LIBERTY:?LIBERTY is required}"
: "${CLOCK_PERIOD:?CLOCK_PERIOD is required}"
: "${ABC_DELAY_PS:?ABC_DELAY_PS is required}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
cd "$repo_root"
out=full-prep-common-out
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
sha256sum --check audit/rom_v44.sha256
sha256sum build/coeff_rom.mem build/square_a.mem build/square_b.mem \
    build/cube.mem | tee "$out/rom-sha256.txt"
sha256sum --check full-prep/common-source-sha256.txt

{
    printf '%s\n' 'COMMON_BOUNDARY=hz_predictor_csa exact production interface'
    printf '%s\n' 'COMMON_INPUT=Divisor[63:0]'
    printf '%s\n' 'COMMON_OUTPUTS=Pred_S[79:0],Pred_C[79:0],Pred_Wrap[7:0],Carry_Low,Is_Power_Boundary'
    printf '%s\n' 'COMMON_CONTENT=bucket,index,generated ROMs,polynomial,signed CSA,Pred outputs,low addition/power-boundary detect'
    printf '%s\n' 'EXCLUDED=V36/V43 product,candidate bank,selector,output registers,FINAL'
    printf '%s\n' 'MAPPING_MODE=yosys-abc-hierarchical-default-single-build'
    printf '%s\n' "MAPPING_INVOCATION=abc -liberty <pinned Nangate45 Liberty> -D $ABC_DELAY_PS"
    printf '%s\n' 'ROM_POLICY=real generated ROM logic mapped once to standard cells; no blackbox, macro, oracle, or area-free source'
    printf '%s\n' 'FREEZE_POLICY=emit once; consume exact artifact; no later ABC/opt/clean across the common block'
} > "$out/common-mapping-contract.txt"

/usr/bin/time -v -o "$out/common-yosys-time.txt" \
yosys -Q -l "$out/yosys.log" -p "
    read_verilog -sv rtl/hz_csa.sv rtl/hz_roms.sv rtl/hz_predictor_csa.sv;
    hierarchy -check -top hz_predictor_csa;
    synth -top hz_predictor_csa -noabc;
    tee -o $out/common_predictor.premap.stat.rpt stat;
    write_json $out/common_predictor.premap.json;
    dfflibmap -liberty $LIBERTY;
    abc -liberty $LIBERTY -D $ABC_DELAY_PS;
    clean;
    tee -o $out/common_predictor.mapped.hier.stat.rpt stat -liberty $LIBERTY;
    write_json $out/common_predictor.mapped.hier.json;
    flatten;
    clean -purge;
    tee -o $out/common_predictor.stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec $out/common_predictor.mapped.v;
    write_json $out/common_predictor.mapped.json;
"

# Re-import exactly the emitted artifact.  This JSON module hash is the
# canonical structure hash used after both variant compositions.
yosys -Q -l "$out/reimport.log" -p "
    read_verilog $out/common_predictor.mapped.v;
    write_json $out/common_predictor.reimport.json;
"

abc_networks=$(grep -c 'Extracting gate netlist of module' "$out/yosys.log")
if (( abc_networks < 2 )); then
    echo "expected separate real predictor and ROM ABC networks, got $abc_networks" >&2
    exit 1
fi
grep -Fq "Extracting gate netlist of module \\hz_predictor_csa" "$out/yosys.log"
grep -Fq "Extracting gate netlist of module \\hz_predictor_roms" "$out/yosys.log"
grep -Fq 'ABC: + scorr' "$out/yosys.log"
grep -Fq 'ABC: + dc2' "$out/yosys.log"
grep -Fq 'ABC: + &nf' "$out/yosys.log"
if grep -Fq 'ABC: + map -D' "$out/yosys.log"; then
    echo 'unexpected abc -fast script detected in canonical common mapping' >&2
    exit 1
fi
printf 'ABC_MAPPED_NETWORKS=%s\n' "$abc_networks" \
    | tee -a "$out/common-mapping-contract.txt"

python3 full-prep/analyze_common.py \
    --directory "$out" --liberty "$LIBERTY" --period "$CLOCK_PERIOD" \
    --output "$out/common_manifest.json"

for evidence in \
    "$out/common_predictor.mapped.v" \
    "$out/common_predictor.mapped.json" \
    "$out/common_predictor.reimport.json" \
    "$out/common_predictor.mapped.hier.json" \
    "$out/common_predictor.premap.json" \
    "$out/common_manifest.json" \
    "$out/common-yosys-time.txt" \
    "$out/yosys.log" \
    "$out/reimport.log"; do
    test -s "$evidence"
done
grep -Eq 'Number of memories:[[:space:]]+0' \
    "$out/common_predictor.premap.stat.rpt" \
    "$out/common_predictor.mapped.hier.stat.rpt" \
    "$out/common_predictor.stat.rpt"
sha256sum --check audit/production_rtl_v44_prep5.sha256
sha256sum --check audit/rom_v44.sha256
