#!/usr/bin/env bash
set -euo pipefail

top="${1:?usage: run_synth.sh <top-module>}"
: "${LIBERTY:?set LIBERTY to the standard-cell .lib file}"

mkdir -p build
python3 scripts/gen_roms.py
python3 scripts/gen_reducers.py
if [[ -n "${RTL_FILES_OVERRIDE:-}" ]]; then
    rtl_files=$RTL_FILES_OVERRIDE
else
    rtl_files=$(find rtl -maxdepth 1 -name '*.sv' -print | sort | tr '\n' ' ')
fi

yosys -Q -l "build/${top}.yosys.log" -p "
    read_verilog -sv $rtl_files build/hz_reducers_generated.sv;
    hierarchy -check -top $top;
    synth -flatten -top $top;
    dfflibmap -liberty $LIBERTY;
    abc -liberty $LIBERTY -D 1000;
    clean -purge;
    read_liberty -lib $LIBERTY;
    hierarchy -check -top $top;
    check -assert;
    tee -o build/${top}.stat.rpt stat -liberty $LIBERTY;
    write_verilog -noattr -noexpr -nodec build/${top}.mapped.v;
    write_json build/${top}.mapped.json;
"

if [[ "${SKIP_OPENSTA:-0}" == "1" ]]; then
    printf '%s\n' "OpenSTA deferred; inspect ABC/Yosys mapping log in this phase." \
        > "build/${top}.sta.rpt"
else
    TOP="$top" sta -no_splash -exit scripts/sta.tcl 2>&1 \
        | tee "build/${top}.sta.rpt"
    if grep -Eq '^(Error:|Error |\[ERROR)' "build/${top}.sta.rpt"; then exit 1; fi
    grep -q '^STA_REPORT_COMPLETE$' "build/${top}.sta.rpt"
fi
