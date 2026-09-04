#!/usr/bin/env bash
set -euo pipefail

variant="${1:?usage: run_sim.sh <36|39|43> [tests]}"
tests="${2:-2000}"
case "$variant" in
    36) top=divider_v36rcm ;;
    39) top=divider_v39c42 ;;
    43) top=divider_v43sj17 ;;
    *) echo "unknown variant: $variant" >&2; exit 2 ;;
esac

mkdir -p build
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
iverilog -g2012 -Wall -s tb_divider -D "DUT_MODULE=$top" \
    -o "build/sim_v${variant}" \
    rtl/*.sv build/hz_reducers_generated.sv tb/tb_divider.sv
vvp "build/sim_v${variant}" "+TESTS=$tests"
