#!/usr/bin/env python3
"""Create the same-run V36/V43 full-PREP mapped comparison."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path("full-prep-out")
V36 = json.loads((ROOT / "v36" / "mapped_metrics.json").read_text())
V43 = json.loads((ROOT / "v43" / "mapped_metrics.json").read_text())

for key in ("top", "clock_period_ns", "boundary_ports", "registered_output_bits",
            "external_candidate_k", "final_included", "rom_representation",
            "rom_content_bits", "liberty_sha256", "wrapper_sha256",
            "mapping_mode", "mapping_invocation", "mapping_network_policy",
            "mapped_common_module_sha256"):
    assert V36[key] == V43[key], (key, V36[key], V43[key])
assert V36["variant"] == 36 and V43["variant"] == 43
assert V36["dff_cells"] == V43["dff_cells"] == 160
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
)
rows = []
deltas = {}
for key in metric_keys:
    v36 = V36[key]
    v43 = V43[key]
    delta = v43 - v36
    percent = (delta / v36 * 100.0) if v36 else None
    rows.append({"metric": key, "v36": v36, "v43": v43,
                 "v43_minus_v36": delta, "v43_vs_v36_percent": percent})
    deltas[key] = {"v36": v36, "v43": v43, "v43_minus_v36": delta,
                   "v43_vs_v36_percent": percent}

comparison = {
    "comparison": "V43 PREP5 full PREP minus V36 PREP5 full PREP",
    "same_run_contract": {
        "top": V36["top"],
        "clock_period_ns": V36["clock_period_ns"],
        "liberty_sha256": V36["liberty_sha256"],
        "wrapper_sha256": V36["wrapper_sha256"],
        "rom_representation": V36["rom_representation"],
        "rom_content_bits": V36["rom_content_bits"],
        "mapping_mode": V36["mapping_mode"],
        "mapped_common_module_sha256": V36["mapped_common_module_sha256"],
    },
    "metrics": deltas,
    "caveat": (
        "region decomposition follows declared hierarchy boundaries; default ABC "
        "optimizes within, not across, those boundaries"
    ),
}
(ROOT / "mapped_comparison.json").write_text(
    json.dumps(comparison, indent=2, sort_keys=True) + "\n")
with (ROOT / "mapped_comparison.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps(comparison, indent=2, sort_keys=True))
