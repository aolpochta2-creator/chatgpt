#!/usr/bin/env bash
set -euo pipefail

top="${1:?usage: run_synth.sh <top-module>}"
: "${LIBERTY:?set LIBERTY to the standard-cell .lib file}"

mkdir -p build
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
rtl_files=$(find rtl -maxdepth 1 -name '*.sv' -print | sort | tr '\n' ' ')

yosys -Q -l "build/${top}.yosys.log" -p "
    read_verilog -sv $rtl_files build/hz_reducers_generated.sv;
    hierarchy -check -top $top;
    synth -flatten -top $top;
    dfflibmap -liberty $LIBERTY;
    abc -liberty $LIBERTY -D 1000;
    clean -purge;
    check;
    tee -o build/${top}.stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec build/${top}.mapped.v;
    write_json build/${top}.mapped.json;
"

if [[ "${SKIP_OPENSTA:-0}" == "1" ]]; then
    printf '%s\n' "OpenSTA deferred; inspect ABC/Yosys mapping log in this phase." \
        > "build/${top}.sta.rpt"
else
    TOP="$top" sta -no_splash -exit scripts/sta.tcl \
        | tee "build/${top}.sta.rpt"
fi
