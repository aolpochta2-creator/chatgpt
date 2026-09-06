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
            "wrapper_sha256", "rom_representation", "rom_content_bits"):
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
        "core_area", "place_density", "liberty_sha256", "wrapper_sha256")},
    "v36_strict_physical_pass": V36["strict_physical_pass"],
    "v36_strict_fail_reasons": V36["strict_fail_reasons"],
    "v43_strict_physical_pass": V43["strict_physical_pass"],
    "v43_strict_fail_reasons": V43["strict_fail_reasons"],
    "metrics": deltas,
    "post_physical_equivalence": "open because LEC_CHECK=0",
}
(ROOT / "physical_comparison.json").write_text(
    json.dumps(comparison, indent=2, sort_keys=True) + "\n")
with (ROOT / "physical_comparison.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps(comparison, indent=2, sort_keys=True))
