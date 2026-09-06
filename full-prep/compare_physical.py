#!/usr/bin/env python3
"""Create a compact same-contract routed V36/V43 full-PREP comparison."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path("full-prep-physical-compare")
V36 = json.loads((ROOT / "v36" / "physical_summary.json").read_text())
V43 = json.loads((ROOT / "v43" / "physical_summary.json").read_text())

for key in ("top", "clock_period_ns", "physical_seed", "drt_or_k",
            "die_area", "core_area", "place_density", "liberty_sha256",
            "wrapper_sha256", "rom_representation", "rom_content_bits",
            "common_mapped_netlist_sha256", "common_manifest_sha256",
            "common_flat_cell_name_type_sha256",
            "production_rtl_lock_sha256", "orfs_image",
            "orfs_platform_commit", "openroad_image_source_commit",
            "openroad_version",
            "nangate45_platform_files_manifest_sha256"):
    assert V36[key] == V43[key], (key, V36[key], V43[key])
assert V36["variant"] == 36 and V43["variant"] == 43
assert V36["measurement_valid"] and V43["measurement_valid"]

metrics = (
    "worst_slack_max_ns",
    "tns_max_ns",
    "worst_slack_min_ns",
    "tns_min_ns",
    "max_data_arrival_ns",
    "logical_cells",
    "logical_cell_area_um2",
    "dffs",
    "routed_wire_length_um",
    "vias",
    "max_capacitance_violations",
    "max_transition_violations",
    "max_fanout_violations",
    "detailed_route_drc_violations",
    "antenna_net_violations",
    "antenna_pin_violations",
    "cts_setup_buffers",
    "cts_hold_buffers",
    "grt_setup_buffers",
    "grt_hold_buffers",
    "grt_repair_design_buffers",
    "flow_runtime_seconds",
    "flow_peak_memory_mb",
)
rows = []
deltas = {}
for key in metrics:
    v36 = float(V36[key])
    v43 = float(V43[key])
    delta = v43 - v36
    percent = delta / v36 * 100.0 if v36 else None
    row = {"metric": key, "v36": V36[key], "v43": V43[key],
           "v43_minus_v36": delta, "v43_vs_v36_percent": percent}
    rows.append(row)
    deltas[key] = row

comparison = {
    "comparison": "V43 PREP5 full PREP minus V36 PREP5 full PREP",
    "contract": {key: V36[key] for key in (
        "clock_period_ns", "physical_seed", "drt_or_k", "die_area",
        "core_area", "place_density", "liberty_sha256", "wrapper_sha256",
        "orfs_image", "orfs_platform_commit", "openroad_image_source_commit",
        "openroad_version", "nangate45_platform_files_manifest_sha256")},
    "drt_command_evidence": {
        "v36": V36["drt_command_evidence"],
        "v43": V43["drt_command_evidence"],
    },
    "v36_strict_physical_pass": V36["strict_physical_pass"],
    "v36_strict_fail_reasons": V36["strict_fail_reasons"],
    "v43_strict_physical_pass": V43["strict_physical_pass"],
    "v43_strict_fail_reasons": V43["strict_fail_reasons"],
    "metrics": deltas,
    "post_physical_equivalence": "open because LEC_CHECK=0",
    "runtime_caveat": (
        "wall time and peak memory are runner/tool diagnostics, not "
        "architecture PPA metrics"
    ),
    "critical_paths": {
        "v36": {
            "startpoint": V36["critical_startpoint"],
            "endpoint": V36["critical_endpoint"],
            "region_sequence": V36["critical_path_region_sequence"],
            "region_cell_counts": V36["critical_path_region_cell_counts"],
            "incremental_cell_delay_by_region_ns":
                V36["critical_path_incremental_cell_delay_by_region_ns"],
            "dominant_region":
                V36["critical_path_dominant_region_by_incremental_cell_delay"],
        },
        "v43": {
            "startpoint": V43["critical_startpoint"],
            "endpoint": V43["critical_endpoint"],
            "region_sequence": V43["critical_path_region_sequence"],
            "region_cell_counts": V43["critical_path_region_cell_counts"],
            "incremental_cell_delay_by_region_ns":
                V43["critical_path_incremental_cell_delay_by_region_ns"],
            "dominant_region":
                V43["critical_path_dominant_region_by_incremental_cell_delay"],
        },
    },
    "final_physical_cost_by_region": {
        "v36": V36["final_physical_cost_by_region"],
        "v43": V43["final_physical_cost_by_region"],
    },
    "electrical_details": {
        label: {key: item[key] for key in (
            "max_capacitance_violations",
            "worst_max_capacitance_slack_ff",
            "max_transition_violations",
            "worst_max_transition_slack_ns",
            "max_fanout_violations",
            "worst_max_fanout_slack",
        )}
        for label, item in (("v36", V36), ("v43", V43))
    },
    "final_artifacts": {
        "v36": {
            "bytes": V36["final_evidence_bytes"],
            "sha256": V36["final_evidence_sha256"],
        },
        "v43": {
            "bytes": V43["final_evidence_bytes"],
            "sha256": V43["final_evidence_sha256"],
        },
    },
}
(ROOT / "physical_comparison.json").write_text(
    json.dumps(comparison, indent=2, sort_keys=True) + "\n")
with (ROOT / "physical_comparison.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps(comparison, indent=2, sort_keys=True))
