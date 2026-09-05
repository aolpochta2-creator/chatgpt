#!/usr/bin/env bash
set -euo pipefail

tests="${1:-500}"
mkdir -p build
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
iverilog -g2012 -Wall -s tb_equivalence \
    -o build/sim_equivalence \
    rtl/*.sv build/hz_reducers_generated.sv tb/tb_equivalence.sv
vvp build/sim_equivalence "+TESTS=$tests"
