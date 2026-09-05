#!/usr/bin/env bash
set -euo pipefail

make generate
mkdir -p build
mapfile -t rtl_files < <(find rtl -maxdepth 1 -name '*.sv' -print | sort)
iverilog -g2012 -DPREP6_REFERENCE_RENAMED -s tb_kernel_prep_reference \
    -o build/tb_kernel_prep_reference \
    "${rtl_files[@]}" physical/prep6_reference_kernel.sv \
    build/hz_reducers_generated.sv \
    tb/tb_kernel_prep_reference.sv
vvp build/tb_kernel_prep_reference | tee build/kernel_prep_reference.rpt
grep -q '^KERNEL_PREP_REFERENCE_PASS ' build/kernel_prep_reference.rpt
