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
common=full-prep-common-out
common_v="$common/common_predictor.mapped.v"
common_manifest="$common/common_manifest.json"
mkdir -p build "$out"

python3 - "$CLOCK_PERIOD" "$ABC_DELAY_PS" "$common_manifest" "$LIBERTY" <<'PY'
import hashlib
import json
import math
import sys
from pathlib import Path

period = float(sys.argv[1])
delay = int(sys.argv[2])
manifest = json.loads(Path(sys.argv[3]).read_text())
liberty = Path(sys.argv[4])
assert math.isfinite(period) and period > 0
assert delay == round(period * 1000), (period, delay)
assert manifest["clock_period_ns"] == period
assert manifest["abc_delay_ps"] == delay
assert manifest["liberty_sha256"] == hashlib.sha256(liberty.read_bytes()).hexdigest()
assert manifest["dff_cells"] == 0 and manifest["memories"] == 0
assert manifest["blackbox_or_oracle"] is False
PY

for evidence in "$common_v" "$common/common_predictor.mapped.json" \
        "$common/common_predictor.reimport.json" "$common_manifest"; do
    test -s "$evidence"
done
sha256sum --check audit/production_rtl_v44_prep5.sha256 \
    | tee "$out/production-rtl-lock.txt"
sha256sum --check full-prep/common-source-sha256.txt
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
sha256sum --check audit/rom_v44.sha256
sha256sum build/coeff_rom.mem build/square_a.mem build/square_b.mem \
    build/cube.mem | tee "$out/rom-sha256.txt"
sha256sum build/hz_reducers_generated.sv full-prep/full_prep_top.sv \
    full-prep/common_predictor_stub.sv | tee "$out/generated-and-wrapper-sha256.txt"

case "$variant" in
    36) product_rtl=rtl/hz_product_v36.sv ;;
    43) product_rtl=rtl/hz_product_v43.sv ;;
esac

{
    printf '%s\n' 'MAPPING_MODE=frozen-common-plus-yosys-abc-hierarchical-default-variant'
    printf '%s\n' "MAPPING_INVOCATION=abc -liberty <pinned Nangate45 Liberty> -D $ABC_DELAY_PS"
    printf '%s\n' 'COMMON_POLICY=consume the one common_mapped artifact; predictor is a blackbox during variant ABC'
    printf '%s\n' 'COMPOSITION_POLICY=overwrite the stub with the exact frozen common Verilog only after all ABC passes'
    printf '%s\n' 'POST_IMPORT_POLICY=flatten/hierarchy/check/write only; no opt, clean, synth, techmap or ABC'
    printf '%s\n' 'ROM_POLICY=real standard-cell logic entirely inside the frozen common artifact'
    printf 'VARIANT_PRODUCT_RTL=%s\n' "$product_rtl"
} > "$out/mapping-contract.txt"

/usr/bin/time -v -o "$out/variant-yosys-time.txt" \
yosys -Q -l "$out/yosys.log" -p "
    read_verilog -sv full-prep/common_predictor_stub.sv rtl/hz_csa.sv \
        rtl/hz_prep.sv rtl/hz_product_v36.sv rtl/hz_product_v39.sv \
        rtl/hz_product_v43.sv build/hz_reducers_generated.sv \
        full-prep/full_prep_top.sv;
    chparam -set VARIANT $variant full_prep_v44;
    hierarchy -check -top full_prep_v44;
    synth -top full_prep_v44 -noabc;
    tee -o $out/premap.stat.rpt stat;
    write_json $out/premap.json;
    dfflibmap -liberty $LIBERTY;
    abc -liberty $LIBERTY -D $ABC_DELAY_PS;
    clean;
    tee -o $out/variant.mapped.hier.stat.rpt stat -liberty $LIBERTY;
    write_json $out/variant.mapped.hier.json;
    write_verilog -noattr -noexpr -nodec $out/variant_only.mapped.v;
    read_verilog -overwrite $common_v;
    tee -o $out/composed.mapped.hier.stat.rpt stat -liberty $LIBERTY;
    write_json $out/mapped.hier.json;
    flatten;
    read_liberty -lib $LIBERTY;
    hierarchy -check -top full_prep_v44;
    check -assert;
    tee -o $out/stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec $out/full_prep_v44.mapped.v;
    write_json $out/full_prep_v44.mapped.json;
"

abc_networks=$(grep -c 'Extracting gate netlist of module' "$out/yosys.log")
if (( abc_networks < 2 )); then
    echo "expected multiple variant-side ABC networks, got $abc_networks" >&2
    exit 1
fi
if grep -Fq "Extracting gate netlist of module \\hz_predictor_csa" "$out/yosys.log" || \
        grep -Fq "Extracting gate netlist of module \\hz_predictor_roms" "$out/yosys.log"; then
    echo 'frozen common predictor/ROM was unexpectedly passed to variant ABC' >&2
    exit 1
fi
grep -Fq 'ABC: + scorr' "$out/yosys.log"
grep -Fq 'ABC: + dc2' "$out/yosys.log"
grep -Fq 'ABC: + &nf' "$out/yosys.log"
if grep -Fq 'ABC: + map -D' "$out/yosys.log"; then
    echo 'unexpected abc -fast script detected' >&2
    exit 1
fi
printf 'ABC_MAPPED_VARIANT_NETWORKS=%s\n' "$abc_networks" \
    | tee -a "$out/mapping-contract.txt"

# The variant-only file must instantiate, but must not redefine, the common
# block.  The exact definition is supplied as the separate frozen artifact.
grep -Fq 'hz_predictor_csa' "$out/variant_only.mapped.v"
if grep -Eq '^module[[:space:]]+hz_predictor_csa' "$out/variant_only.mapped.v"; then
    echo 'variant-only artifact unexpectedly embeds the common definition' >&2
    exit 1
fi

for evidence in \
    "$out/yosys.log" \
    "$out/variant-yosys-time.txt" \
    "$out/premap.stat.rpt" \
    "$out/premap.json" \
    "$out/variant.mapped.hier.stat.rpt" \
    "$out/variant.mapped.hier.json" \
    "$out/variant_only.mapped.v" \
    "$out/composed.mapped.hier.stat.rpt" \
    "$out/mapped.hier.json" \
    "$out/mapping-contract.txt" \
    "$out/stat.rpt" \
    "$out/full_prep_v44.mapped.v" \
    "$out/full_prep_v44.mapped.json"; do
    test -s "$evidence"
done
grep -Eq 'Number of memories:[[:space:]]+0' "$out/premap.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/variant.mapped.hier.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/composed.mapped.hier.stat.rpt"
grep -Eq 'Number of memories:[[:space:]]+0' "$out/stat.rpt"
sha256sum --check audit/production_rtl_v44_prep5.sha256
