#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
cd "$repo_root"

if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" ]]; then
    echo "full-PREP gate must run from the checked-out repository root" >&2
    exit 1
fi

tests="${1:-256}"
mkdir -p build full-prep-out
exec > >(tee full-prep-out/functional.log) 2>&1

echo "== byte-locked production RTL =="
sha256sum --check audit/production_rtl_v44_prep5.sha256

echo "== deterministic ROM and reducer generation =="
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
rom_files=(
    build/coeff_rom.mem
    build/square_a.mem
    build/square_b.mem
    build/cube.mem
)
for rom in "${rom_files[@]}"; do
    test -s "$rom"
done
test "$(wc -l < build/coeff_rom.mem)" -eq 64
test "$(wc -l < build/square_a.mem)" -eq 256
test "$(wc -l < build/square_b.mem)" -eq 32
test "$(wc -l < build/cube.mem)" -eq 256
sha256sum --check audit/rom_v44.sha256
sha256sum "${rom_files[@]}" | tee full-prep-out/rom-sha256.txt
sha256sum build/hz_reducers_generated.sv full-prep/full_prep_top.sv \
    | tee full-prep-out/generated-and-wrapper-sha256.txt

echo "== compile and execute full-PREP boundary =="
iverilog -g2012 -Wall -s tb_full_prep \
    -o build/full_prep_sim \
    rtl/*.sv build/hz_reducers_generated.sv \
    full-prep/full_prep_top.sv full-prep/tb_full_prep.sv \
    2>&1 | tee full-prep-out/icarus-compile.log
vvp build/full_prep_sim "+TESTS=$tests" \
    | tee full-prep-out/icarus-run.log
grep -q '^PASS full-PREP V36/V43 exact registered equivalence' \
    full-prep-out/icarus-run.log
if grep -E -i 'unable to open|readmemh[^[:cntrl:]]*(error|warning)' \
    full-prep-out/icarus-compile.log full-prep-out/icarus-run.log; then
    echo "ROM initialization warning found in full-PREP logs" >&2
    exit 1
fi

echo "== final source locks =="
sha256sum --check audit/production_rtl_v44_prep5.sha256
sha256sum --check audit/rom_v44.sha256
printf '%s\n' \
    'FULL_PREP_FUNCTIONAL=PASS' \
    'VARIANTS=36,43' \
    'BOUNDARY=production hz_prep plus identical 160-bit output register bank' \
    'FINAL_INCLUDED=no' \
    'EXTERNAL_CANDIDATE_K=no' \
    'PRODUCTION_RTL_CHANGE=none' \
    | tee full-prep-out/functional-summary.txt
