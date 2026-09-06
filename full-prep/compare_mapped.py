#!/usr/bin/env python3
"""Enforce frozen-common fairness, then compare same-run mapped variants."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


ROOT = Path("full-prep-out")
COMMON_ROOT = Path("full-prep-common-out")
V36 = json.loads((ROOT / "v36" / "mapped_metrics.json").read_text())
V43 = json.loads((ROOT / "v43" / "mapped_metrics.json").read_text())
COMMON = json.loads((COMMON_ROOT / "common_manifest.json").read_text())


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


for key in (
    "top",
    "clock_period_ns",
    "boundary_ports",
    "registered_output_bits",
    "external_candidate_k",
    "final_included",
    "rom_representation",
    "rom_content_bits",
    "rom_sha256",
    "liberty_sha256",
    "wrapper_sha256",
    "mapping_mode",
    "mapping_invocation",
    "mapping_network_policy",
    "common_netlist_naming_policy",
    "mapped_common_module_sha256",
    "common_mapped_verilog_sha256",
    "common_manifest_sha256",
    "common_source_manifest_sha256",
    "common_production_rtl_lock_sha256",
    "common_reimport_module_json_sha256",
    "common_flat_cell_count",
    "common_flat_cell_name_type_sha256",
    "common_cell_name_hash_canonicalization",
    "common_dff_cells",
    "common_boundary_ports",
    "mapped_tool_versions_sha256",
    "gate_trace_sha256",
    "gate_vector_count",
):
    assert V36[key] == V43[key], (key, V36[key], V43[key])

assert V36["variant"] == 36 and V43["variant"] == 43
assert V36["dff_cells"] == V43["dff_cells"] == 160
assert V36["gate_level_functional_pass"]
assert V43["gate_level_functional_pass"]
assert V36["mapped_memories"] == V43["mapped_memories"] == 0

# Fairness/provenance gate.  The one common artifact is independently hashed
# at creation, at both composition points, and again in this comparison job.
common_v = COMMON_ROOT / "common_predictor.mapped.v"
common_json = COMMON_ROOT / "common_predictor.mapped.json"
assert sha256(common_v) == COMMON["mapped_verilog_sha256"]
assert sha256(common_json) == COMMON["mapped_json_sha256"]
assert sha256(COMMON_ROOT / "common_manifest.json") == \
    V36["common_manifest_sha256"]
assert COMMON["mapped_verilog_sha256"] == \
    V36["common_mapped_verilog_sha256"]
assert COMMON["reimport_module_json_sha256"] == \
    V36["common_reimport_module_json_sha256"]
assert COMMON["reimport_cell_name_type_sha256"] == \
    V36["common_flat_cell_name_type_sha256"]
assert COMMON["source_manifest_sha256"] == \
    V36["common_source_manifest_sha256"]
assert COMMON["production_rtl_lock_sha256"] == \
    V36["common_production_rtl_lock_sha256"]
assert COMMON["liberty_sha256"] == V36["liberty_sha256"]
assert COMMON["clock_period_ns"] == V36["clock_period_ns"]
assert COMMON["mapping_invocation"].endswith(
    f"-D {COMMON['abc_delay_ps']}")
assert COMMON["boundary_ports"] == V36["common_boundary_ports"]
assert COMMON["dff_cells"] == V36["common_dff_cells"] == 0
assert COMMON["memories"] == 0
assert COMMON["blackbox_or_oracle"] is False
assert COMMON["netlist_naming_policy"] == \
    V36["common_netlist_naming_policy"]
assert COMMON["cell_name_hash_canonicalization"] == \
    V36["common_cell_name_hash_canonicalization"]
assert COMMON["mapped_tool_versions_sha256"] == \
    V36["mapped_tool_versions_sha256"]
assert COMMON["rom_sha256"] == V36["rom_sha256"]

for key in (
    "common_rom_logical_cells",
    "common_rom_logical_area_um2",
    "common_predictor_non_rom_logical_cells",
    "common_predictor_non_rom_logical_area_um2",
):
    assert V36[key] == V43[key], (key, V36[key], V43[key])

metric_keys = (
    "logical_cells",
    "logical_area_um2",
    "dff_cells",
    "max_data_arrival_ns",
    "worst_setup_slack_ns",
    "setup_tns_ns",
    "max_data_fanout_excluding_clock_reset",
    "premap_generic_cells",
    "mapped_explicit_mux_cells",
    "common_rom_logical_cells",
    "common_rom_logical_area_um2",
    "common_predictor_non_rom_logical_cells",
    "common_predictor_non_rom_logical_area_um2",
    "common_candidate_selector_and_special_logical_cells",
    "common_candidate_selector_and_special_logical_area_um2",
    "product_specific_logical_cells",
    "product_specific_logical_area_um2",
    "variant_yosys_wall_seconds",
    "variant_yosys_peak_rss_kb",
    "variant_abc_reported_cpu_seconds",
)
rows = []
deltas = {}
for key in metric_keys:
    v36 = V36[key]
    v43 = V43[key]
    if v36 is None or v43 is None:
        delta = None
        percent = None
    else:
        delta = v43 - v36
        percent = (delta / v36 * 100.0) if v36 else None
    rows.append({
        "metric": key,
        "v36": v36,
        "v43": v43,
        "v43_minus_v36": delta,
        "v43_vs_v36_percent": percent,
    })
    deltas[key] = {
        "v36": v36,
        "v43": v43,
        "v43_minus_v36": delta,
        "v43_vs_v36_percent": percent,
    }

fairness = {
    "status": "PASS",
    "common_source_sha256": COMMON["source_manifest_sha256"],
    "rom_sha256": COMMON["rom_sha256"],
    "common_mapped_verilog_sha256": COMMON["mapped_verilog_sha256"],
    "common_reimport_module_json_sha256":
        COMMON["reimport_module_json_sha256"],
    "common_flat_cell_name_type_sha256":
        COMMON["reimport_cell_name_type_sha256"],
    "common_cell_name_hash_canonicalization":
        COMMON["cell_name_hash_canonicalization"],
    "liberty_sha256": COMMON["liberty_sha256"],
    "mapped_tool_versions_sha256": COMMON["mapped_tool_versions_sha256"],
    "netlist_naming_policy": COMMON["netlist_naming_policy"],
    "timing_target_ns": COMMON["clock_period_ns"],
    "abc_delay_ps": COMMON["abc_delay_ps"],
    "common_dff_cells": COMMON["dff_cells"],
    "common_boundary_ports": COMMON["boundary_ports"],
    "residual_memories": COMMON["memories"],
    "production_rtl_lock_sha256": COMMON["production_rtl_lock_sha256"],
    "gate_trace_sha256": V36["gate_trace_sha256"],
    "gate_vector_count": V36["gate_vector_count"],
    "proof": (
        "one common_mapped job emitted one real standard-cell predictor/ROM "
        "artifact; both variants consumed that byte-identical file after all "
        "variant ABC passes, and the post-flatten name/type fingerprints match"
    ),
}
comparison = {
    "comparison": "V43 PREP5 full PREP minus V36 PREP5 full PREP",
    "fairness_gate": fairness,
    "same_run_contract": {
        "top": V36["top"],
        "clock_period_ns": V36["clock_period_ns"],
        "liberty_sha256": V36["liberty_sha256"],
        "wrapper_sha256": V36["wrapper_sha256"],
        "rom_representation": V36["rom_representation"],
        "rom_content_bits": V36["rom_content_bits"],
        "mapping_mode": V36["mapping_mode"],
    },
    "common_mapping": {
        "logical_cells": COMMON["logical_cells"],
        "logical_area_um2": COMMON["logical_area_um2"],
        "dff_cells": COMMON["dff_cells"],
        "cost_by_region": COMMON["cost_by_region"],
        "yosys_wall_seconds": COMMON["yosys_wall_seconds"],
        "yosys_peak_rss_kb": COMMON["yosys_peak_rss_kb"],
        "abc_reported_cpu_seconds": COMMON["abc_reported_cpu_seconds"],
    },
    "critical_paths": {
        "v36": V36["critical_path"],
        "v43": V43["critical_path"],
    },
    "metrics": deltas,
    "caveat": (
        "the frozen predictor boundary prevents cross-boundary Boolean "
        "optimization; all real common gates and timing arcs remain present"
    ),
    "runtime_caveat": (
        "mapping wall time and peak RSS are CI diagnostics, not architecture "
        "quality metrics"
    ),
}
(ROOT / "mapped_comparison.json").write_text(
    json.dumps(comparison, indent=2, sort_keys=True) + "\n")
with (ROOT / "mapped_comparison.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps(comparison, indent=2, sort_keys=True))
print("FULL_PREP_COMMON_FAIRNESS=PASS")
