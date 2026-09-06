#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
cd "$repo_root"

if [[ "$(git rev-parse --show-toplevel)" != "$repo_root" ]]; then
    echo "audit must run from the checked-out repository root" >&2
    exit 1
fi

mkdir -p build audit-out
exec > >(tee audit-out/compiled-rtl-audit.log) 2>&1

echo "== tool provenance =="
{
    printf 'repository_root=%s\n' "$repo_root"
    printf 'source_commit=%s\n' "$(git rev-parse HEAD)"
    printf 'runner_os=%s\n' "$(uname -a)"
    printf 'actions_image_os=%s\n' "${ImageOS:-unknown}"
    printf 'actions_image_version=%s\n' "${ImageVersion:-unknown}"
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='package=${Package} version=${Version} arch=${Architecture}\n' \
            iverilog verilator yosys
    fi
    iverilog -V
    vvp -V
    verilator --version
    yosys -V
} 2>&1 | tee audit-out/tool-versions.txt

echo "== production RTL byte lock =="
sha256sum --check audit/production_rtl_v44_prep5.sha256 | tee audit-out/production-rtl-lock.txt

echo "== deterministic ROM/reducer generation =="
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
sha256sum "${rom_files[@]}" | tee audit-out/rom-sha256.txt
sha256sum build/hz_reducers_generated.sv | tee audit-out/reducer-sha256.txt

echo "== mathematical/model regressions =="
PYTHONPATH=. python3 scripts/validate_model.py | tee audit-out/model-validation.log
PYTHONPATH=. python3 scripts/validate_structure.py | tee audit-out/structural-validation.log
PYTHONPATH=. python3 audit/validate_directed_vectors.py | tee audit-out/directed-model-validation.log

rtl_files=(rtl/*.sv build/hz_reducers_generated.sv)

echo "== Icarus expression-sizing microtest =="
iverilog -g2012 -Wall -s tb_expression_sizing \
    -o build/audit_expression_sizing audit/tb_expression_sizing.sv \
    2>&1 | tee audit-out/icarus-expression-compile.log
vvp build/audit_expression_sizing | tee audit-out/icarus-expression-run.log

echo "== Icarus V43 finite directed test =="
iverilog -g2012 -Wall -s tb_v43_directed \
    -o build/audit_v43_directed \
    "${rtl_files[@]}" audit/tb_v43_directed.sv \
    2>&1 | tee audit-out/icarus-v43-directed-compile.log
vvp build/audit_v43_directed | tee audit-out/icarus-v43-directed-run.log

echo "== Icarus post-NBA pipeline contract =="
iverilog -g2012 -Wall -s tb_pipeline_contract \
    -o build/audit_pipeline_contract \
    "${rtl_files[@]}" audit/tb_pipeline_contract.sv \
    2>&1 | tee audit-out/icarus-pipeline-compile.log
vvp build/audit_pipeline_contract | tee audit-out/icarus-pipeline-run.log

echo "== Icarus full-top and cross-variant regressions =="
for variant in 36 39 43; do
    bash scripts/run_sim.sh "$variant" 250 2>&1 | tee "audit-out/icarus-v${variant}.log"
done
bash scripts/run_equivalence.sh 250 2>&1 | tee audit-out/icarus-equivalence.log

if grep -E -i 'unable to open|readmemh[^[:cntrl:]]*(error|warning)' audit-out/icarus-*.log; then
    echo "ROM initialization warning found in Icarus logs" >&2
    exit 1
fi

echo "== Verilator execution of the same sizing microtest =="
verilator --binary --timing --top-module tb_expression_sizing \
    -Wall -Wno-fatal --Mdir build/verilator_expression -o sim_expression \
    audit/tb_expression_sizing.sv \
    2>&1 | tee audit-out/verilator-expression-build.log
build/verilator_expression/sim_expression | tee audit-out/verilator-expression-run.log

echo "== Verilator production RTL lint =="
verilator_logs=()
for top in divider_v36rcm divider_v39c42 divider_v43sj17; do
    log="audit-out/verilator-${top}.log"
    verilator_logs+=("$log")
    verilator --lint-only --sv --top-module "$top" -Wall -Wno-fatal \
        "${rtl_files[@]}" 2>&1 | tee "$log"
done
python3 audit/classify_verilator_warnings.py \
    "${verilator_logs[@]}" --output audit-out/verilator-warning-classification.tsv

echo "== Yosys full-top elaboration and critical width/type inspection =="
rtl_arg=$(printf '%s ' "${rtl_files[@]}")
rtlil_files=()
for top in divider_v36rcm divider_v39c42 divider_v43sj17; do
    rtlil="audit-out/${top}.elaborated.il"
    rtlil_files+=("$rtlil")
    yosys -Q -l "audit-out/yosys-${top}.log" -p "
        read_verilog -sv $rtl_arg;
        hierarchy -check -top $top;
        proc;
        check -assert;
        write_rtlil $rtlil;
    "
    test -s "$rtlil"
done
python3 audit/check_yosys_elaboration.py \
    "${rtlil_files[@]}" --output audit-out/yosys-elaborated-widths.tsv

echo "== final locks and stage statement =="
sha256sum --check audit/production_rtl_v44_prep5.sha256
sha256sum --check audit/rom_v44.sha256
{
    echo "COMPILED_RTL_AUDIT=PASS"
    echo "PRODUCTION_RTL_FUNCTIONAL_CHANGE=none (sha256 manifest matched before and after)"
    echo "PHYSICAL_FLOW_RUN=no"
    echo "FORMAL_PROOF_GATE=open; no whole-divider SMT claim was attempted"
    echo "POST_PHYSICAL_LEC_GATE=open"
} | tee audit-out/stage-summary.txt
