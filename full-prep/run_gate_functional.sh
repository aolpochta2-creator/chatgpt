#!/usr/bin/env bash
set -euo pipefail

variant="${1:?usage: run_gate_functional.sh <36|43> [random-tests]}"
tests="${2:-32}"
if [[ "$variant" != 36 && "$variant" != 43 ]]; then
    echo "variant must be 36 or 43" >&2
    exit 1
fi
: "${LIBERTY:?LIBERTY is required}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
cd "$repo_root"
out="full-prep-out/v${variant}"
common=full-prep-common-out/common_predictor.mapped.v
variant_netlist="$out/variant_only.mapped.v"
cell_models="$out/nangate45-functional-models.v"

for input in "$LIBERTY" "$common" "$variant_netlist"; do
    test -s "$input"
done

# Yosys's pinned Liberty frontend creates Boolean/sequential simulation models
# from the exact mapping Liberty; no unrelated binary model is downloaded.
# Nangate45 also contains unused special cells (for example CLKGATETST_X1)
# whose internal output has no Boolean ``function``.  Skip only such cells;
# Icarus still rejects the composed netlist if any actually instantiated cell
# lacks a generated model.
yosys -Q -l "$out/liberty-models.log" -p "
    read_liberty -ignore_miss_func $LIBERTY;
    write_verilog -noattr $cell_models;
"
test -s "$cell_models"

iverilog -g2012 -Wall -s tb_full_prep_gate \
    -o "$out/full_prep_gate_sim" \
    "$cell_models" "$common" "$variant_netlist" \
    full-prep/tb_full_prep_gate.sv \
    2>&1 | tee "$out/gate-compile.log"
vvp "$out/full_prep_gate_sim" "+VARIANT=$variant" "+TESTS=$tests" \
    | tee "$out/gate-run.log"
grep -q "^PASS mapped full-PREP V${variant} exact registered" \
    "$out/gate-run.log"
grep '^GATE_VECTOR ' "$out/gate-run.log" > "$out/gate-trace.txt"
test "$(wc -l < "$out/gate-trace.txt")" -eq $((tests + 9))
sha256sum "$out/gate-trace.txt" "$cell_models" \
    | tee "$out/gate-functional-sha256.txt"
