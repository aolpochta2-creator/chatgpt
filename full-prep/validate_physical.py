#!/usr/bin/env python3
"""Validate one routed full-PREP measurement without hiding strict failures."""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import sys
from collections import Counter
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


root = Path(sys.argv[1])
top = "full_prep_v44"
variant = int(os.environ["VARIANT"])
expected_period = float(os.environ["CLOCK_PERIOD"])
source_commit = os.environ["SOURCE_COMMIT"]
source_run_id = int(os.environ["SOURCE_RUN_ID"])
physical_seed = int(os.environ["PHYSICAL_SEED"])
drt_or_k = float(os.environ["DRT_OR_K"])
flow_runtime_seconds = int(os.environ["FLOW_RUNTIME_SECONDS"])
assert variant in (36, 43)
assert math.isclose(expected_period, 15.0, abs_tol=1e-12)
assert physical_seed == 1 and math.isclose(drt_or_k, 1.0, abs_tol=1e-12)
assert re.fullmatch(r"[0-9a-f]{40}", source_commit)
assert source_run_id > 0 and flow_runtime_seconds > 0

reports = root / "reports" / "nangate45" / top / "base"
results = root / "results" / "nangate45" / top / "base"
logs = root / "logs" / "nangate45" / top / "base"
evidence_names = ["6_final.odb", "6_final.def", "6_final.gds",
                  "6_final.v", "6_final.sdc", "6_final.spef"]
evidence_sizes = {}
for name in evidence_names:
    path = results / name
    assert path.is_file() and path.stat().st_size > 0, f"missing evidence: {path}"
    evidence_sizes[name] = path.stat().st_size

final_sdc = (results / "6_final.sdc").read_text()
period_match = re.search(r"create_clock\s+.*?-period\s+([0-9.]+)", final_sdc)
assert period_match
actual_period = float(period_match.group(1))
assert math.isclose(actual_period, expected_period, abs_tol=0.0001)

counts = dict(line.split("\t") for line in
              (reports / "physical_counts.tsv").read_text().splitlines())
assert int(counts["dffs"]) == 160
counts = {
    "logical_cells": int(counts["logical_cells"]),
    "total_cells_including_fillers": int(counts["total_cells_including_fillers"]),
    "dffs": int(counts["dffs"]),
    "logical_cell_area_um2": float(counts["logical_cell_area_um2"]),
}
cell_types = dict(line.split("\t") for line in
                  (reports / "physical_cell_types.tsv").read_text().splitlines())

slack_report = (reports / "physical_slack.rpt").read_text()
timing = {}
for kind in ("max", "min"):
    match = re.search(rf"worst slack {kind}\s+(-?\d+\.\d+)", slack_report)
    assert match, f"missing {kind} slack"
    timing[f"worst_slack_{kind}_ns"] = float(match.group(1))
for kind in ("max", "min"):
    match = re.search(rf"tns {kind}\s+(-?\d+\.\d+)", slack_report)
    assert match, f"missing {kind} TNS"
    timing[f"tns_{kind}_ns"] = float(match.group(1))

setup = (reports / "physical_setup.rpt").read_text()
hold = (reports / "physical_hold.rpt").read_text()
assert "Startpoint:" in setup and "Endpoint:" in setup
assert "Startpoint:" in hold and "Endpoint:" in hold
critical_startpoint = re.search(r"^Startpoint:\s+(.+)$", setup, re.MULTILINE).group(1)
critical_endpoint = re.search(r"^Endpoint:\s+(.+)$", setup, re.MULTILINE).group(1)
next_path = setup.find("\nStartpoint:", 1)
critical_path = setup if next_path < 0 else setup[:next_path]
critical_data_path = critical_path.split("data arrival time", 1)[0]
critical_cells = []
seen_instances = set()
for instance, cell_type in re.findall(
        r"[\^v]\s+(\S+)/\S+\s+\(([A-Z][A-Z0-9_]*_X\d+)\)",
        critical_data_path):
    if instance not in seen_instances:
        critical_cells.append((instance, cell_type))
        seen_instances.add(instance)
critical_cell_types = [cell_type for _, cell_type in critical_cells]
critical_fanouts = [int(value) for value in re.findall(
    r"^\s+(\d+)\s+-?\d+\.\d+\s+", critical_data_path, re.MULTILINE)]
arrivals = [float(value) for value in re.findall(
    r"^\s+(-?\d+\.\d+)\s+data arrival time\s*$", setup, re.MULTILINE)]
arrivals = [value for value in arrivals if value >= 0.0]
assert arrivals

mapped_json = json.loads(Path(
    f"full-prep-out/v{variant}/full_prep_v44.mapped.json").read_text())
mapped_cells = mapped_json["modules"][top]["cells"]
path_source_files = Counter()
matched_path_instances = 0
for instance, _ in critical_cells:
    cell = mapped_cells.get(instance) or mapped_cells.get(instance.lstrip("\\"))
    if cell is None:
        continue
    matched_path_instances += 1
    src = str(cell.get("attributes", {}).get("src", ""))
    match = re.search(r"([^|\s]+\.sv):\d+", src)
    path_source_files[match.group(1) if match else "unattributed"] += 1

electrical = (reports / "physical_electrical.rpt").read_text()
electrical_sections = {
    "max slew": ("max_transition_violations", "worst_max_transition_slack_ns"),
    "max capacitance": ("max_capacitance_violations", "worst_max_capacitance_slack_ff"),
    "max fanout": ("max_fanout_violations", "worst_max_fanout_slack"),
}
electrical_counts = {item[0]: 0 for item in electrical_sections.values()}
electrical_slacks = {item[1]: None for item in electrical_sections.values()}
electrical_violators = {item[0]: [] for item in electrical_sections.values()}
section = None
for line in electrical.splitlines():
    heading = line.strip().lower()
    if heading in electrical_sections:
        section = electrical_sections[heading]
    elif "(VIOLATED)" in line:
        assert section
        electrical_counts[section[0]] += 1
        match = re.search(r"(-?(?:\d+(?:\.\d*)?|\.\d+))\s+\(VIOLATED\)", line)
        assert match
        value = float(match.group(1))
        previous = electrical_slacks[section[1]]
        electrical_slacks[section[1]] = value if previous is None else min(previous, value)
        electrical_violators[section[0]].append(line.strip())

route = (logs / "5_2_route.log").read_text()
wire = re.findall(r"Total wire length =\s*(\d+)\s*um\.", route)
vias = re.findall(r"Total number of vias =\s*(\d+)\.", route)
antenna_nets = re.findall(r"Found (\d+) net violations\.", route)
antenna_pins = re.findall(r"Found (\d+) pin violations\.", route)
assert wire and vias and antenna_nets and antenna_pins
drt_commands = [line.strip() for line in route.splitlines()
                if "detailed_route" in line and "-or_seed" in line]
assert drt_commands, "actual detailed_route seed command not found"
assert any(re.search(r"-or_seed\s+1(?:\s|$)", line) and
           re.search(r"-or_k\s+1(?:\.0+)?(?:\s|$)", line)
           for line in drt_commands), drt_commands

drc_text = (reports / "5_route_drc.rpt").read_text()
drc_violations = len(re.findall(r"^violation type:", drc_text, re.MULTILINE))
cts = (logs / "4_1_cts.log").read_text()
grt = (logs / "5_1_grt.log").read_text()
cts_repair_calls = len(re.findall(r"^repair_timing\s", cts, re.MULTILINE))
assert cts_repair_calls > 0
cts_setup_buffers = sum(map(int, re.findall(
    r"\[INFO RSZ-0040\] Inserted (\d+) buffers\.", cts)))
cts_hold_buffers = sum(map(int, re.findall(r"Inserted (\d+) hold buffers\.", cts)))
grt_setup_buffers = sum(map(int, re.findall(
    r"\[INFO RSZ-0040\] Inserted (\d+) buffers\.", grt)))
grt_hold_buffers = sum(map(int, re.findall(r"Inserted (\d+) hold buffers\.", grt)))
grt_design_buffers = sum(map(int, re.findall(
    r"Inserted (\d+) buffers in \d+ nets\.", grt)))

mapped_metrics_path = Path(f"full-prep-out/v{variant}/mapped_metrics.json")
mapped_metrics = json.loads(mapped_metrics_path.read_text())
summary = {
    "experiment": "V44 full-PREP integration/ranking",
    "variant": variant,
    "top": top,
    "source_commit": source_commit,
    "source_run_id": source_run_id,
    "clock_period_ns": actual_period,
    "physical_seed": physical_seed,
    "drt_or_k": drt_or_k,
    "drt_random_order_active": True,
    "drt_command_evidence": drt_commands,
    "die_area": os.environ["DIE_AREA"],
    "core_area": os.environ["CORE_AREA"],
    "place_density": float(os.environ["PLACE_DENSITY"]),
    "flow_runtime_seconds": flow_runtime_seconds,
    **counts,
    **timing,
    "max_data_arrival_ns": max(arrivals),
    "critical_startpoint": critical_startpoint,
    "critical_endpoint": critical_endpoint,
    "critical_path_logic_cell_count": len(critical_cell_types),
    "critical_path_buffer_count": sum(
        cell.startswith("BUF_") for cell in critical_cell_types),
    "critical_path_max_fanout": max(critical_fanouts, default=0),
    "critical_path_cell_types": critical_cell_types,
    "critical_path_instances_matched_to_mapped_json": matched_path_instances,
    "critical_path_source_file_counts": dict(sorted(path_source_files.items())),
    **electrical_counts,
    **electrical_slacks,
    "max_capacitance_violators": electrical_violators["max_capacitance_violations"],
    "electrical_violations": sum(electrical_counts.values()),
    "cts_repair_timing_calls": cts_repair_calls,
    "cts_setup_buffers": cts_setup_buffers,
    "cts_hold_buffers": cts_hold_buffers,
    "grt_setup_buffers": grt_setup_buffers,
    "grt_hold_buffers": grt_hold_buffers,
    "grt_repair_design_buffers": grt_design_buffers,
    "routed_wire_length_um": int(wire[-1]),
    "vias": int(vias[-1]),
    "detailed_route_drc_violations": drc_violations,
    "antenna_net_violations": int(antenna_nets[-1]),
    "antenna_pin_violations": int(antenna_pins[-1]),
    "final_evidence_bytes": evidence_sizes,
    "final_cell_type_counts": {key: int(value) for key, value in cell_types.items()},
    "mapped_metrics_sha256": sha256(mapped_metrics_path),
    "mapped_netlist_sha256": sha256(Path(
        f"full-prep-out/v{variant}/full_prep_v44.mapped.v")),
    "liberty_sha256": mapped_metrics["liberty_sha256"],
    "wrapper_sha256": mapped_metrics["wrapper_sha256"],
    "rom_representation": mapped_metrics["rom_representation"],
    "rom_content_bits": mapped_metrics["rom_content_bits"],
    "measurement_valid": True,
    "evidence": "full route, OpenRCX SPEF and final single-typical-corner STA",
    "post_physical_equivalence": "open because LEC_CHECK=0",
}

fail_reasons = []
if summary["worst_slack_max_ns"] < 0:
    fail_reasons.append("setup")
if summary["worst_slack_min_ns"] < 0:
    fail_reasons.append("hold")
if summary["tns_max_ns"] != 0.0:
    fail_reasons.append("setup_tns")
if summary["tns_min_ns"] != 0.0:
    fail_reasons.append("hold_tns")
if summary["max_capacitance_violations"]:
    fail_reasons.append("max_capacitance")
if summary["max_transition_violations"]:
    fail_reasons.append("max_transition")
if summary["max_fanout_violations"]:
    fail_reasons.append("max_fanout")
if summary["detailed_route_drc_violations"]:
    fail_reasons.append("detailed_route_drc")
if summary["antenna_net_violations"] or summary["antenna_pin_violations"]:
    fail_reasons.append("antenna")
summary["strict_physical_pass"] = not fail_reasons
summary["strict_fail_reasons"] = fail_reasons
(root / "physical_summary.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n")
print(json.dumps(summary, indent=2, sort_keys=True))
print("FULL_PREP_MEASUREMENT_VALID")
print("FULL_PREP_STRICT_PASS" if not fail_reasons else
      "FULL_PREP_STRICT_FAIL=" + ",".join(fail_reasons))
