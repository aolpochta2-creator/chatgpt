#!/usr/bin/env bash
set -euo pipefail

make generate
mkdir -p build
mapfile -t rtl_files < <(find rtl -maxdepth 1 -name '*.sv' -print | sort)
sed \
    -e 's/kernel_v36rcm/kernel_v36rcm_prep6_ref/g' \
    -e 's/kernel_v39c42/kernel_v39c42_prep6_ref/g' \
    -e 's/kernel_v43sj17/kernel_v43sj17_prep6_ref/g' \
    -e 's/hz_kernel_core/hz_kernel_core_prep6_ref/g' \
    physical/prep6_reference_kernel.sv \
    > build/prep6_reference_kernel_renamed.sv
iverilog -g2012 -s tb_kernel_prep_reference \
    -o build/tb_kernel_prep_reference \
    "${rtl_files[@]}" build/prep6_reference_kernel_renamed.sv \
    build/hz_reducers_generated.sv \
    tb/tb_kernel_prep_reference.sv
vvp build/tb_kernel_prep_reference | tee build/kernel_prep_reference.rpt
grep -q '^KERNEL_PREP_REFERENCE_PASS ' build/kernel_prep_reference.rpt
