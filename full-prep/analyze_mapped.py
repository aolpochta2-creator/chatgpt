#!/usr/bin/env python3
"""Validate and enrich one mapped full-PREP checkpoint."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_manifest(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        result[name] = digest
    return result


def normalized_instance(name: str) -> str:
    """Normalize Yosys dot paths and OpenSTA slash paths for matching."""
    return name.replace("/", ".").replace("\\", "").lstrip(".")


def stat_value(text: str, label: str) -> int:
    match = re.search(rf"{re.escape(label)}:\s+(\d+)", text)
    if not match:
        raise ValueError(f"missing {label!r} in Yosys stat")
    return int(match.group(1))


def time_metrics(path: Path, log_path: Path) -> dict[str, float | int | None]:
    text = path.read_text()
    log = log_path.read_text()
    user = re.search(r"User time \(seconds\):\s*([0-9.]+)", text)
    system = re.search(r"System time \(seconds\):\s*([0-9.]+)", text)
    elapsed = re.search(r"Elapsed \(wall clock\) time .*?:\s*([0-9:.]+)", text)
    rss = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    abc = re.search(r"\b1x abc \(([0-9.]+) sec\)", log)
    assert user and system and elapsed and rss
    parts = [float(part) for part in elapsed.group(1).split(":")]
    wall = sum(value * (60 ** index)
               for index, value in enumerate(reversed(parts)))
    return {
        "variant_yosys_user_cpu_seconds": float(user.group(1)),
        "variant_yosys_system_cpu_seconds": float(system.group(1)),
        "variant_yosys_wall_seconds": wall,
        "variant_yosys_peak_rss_kb": int(rss.group(1)),
        "variant_abc_reported_cpu_seconds": float(abc.group(1)) if abc else None,
    }


def source_file(cell: dict) -> str:
    src = str(cell.get("attributes", {}).get("src", ""))
    match = re.search(r"([^|\s]+\.sv):\d+", src)
    return match.group(1) if match else "unattributed"


def cell_source_counts(module: dict) -> dict[str, int]:
    return dict(sorted(Counter(source_file(cell) for cell in
                               module.get("cells", {}).values()).items()))


def liberty_metadata(path: Path) -> tuple[dict[str, dict[str, str]], dict[str, float]]:
    text = path.read_text()
    directions: dict[str, dict[str, str]] = {}
    areas: dict[str, float] = {}
    cell_pattern = re.compile(r"\bcell\s*\(\s*([^\s)]+)\s*\)\s*\{")
    pin_pattern = re.compile(r"\bpin\s*\(\s*([^\s)]+)\s*\)\s*\{")

    def blocks(body: str, pattern: re.Pattern[str]):
        for match in pattern.finditer(body):
            depth = 1
            index = match.end()
            while index < len(body) and depth:
                depth += (body[index] == "{") - (body[index] == "}")
                index += 1
            if depth:
                raise ValueError("unterminated Liberty block")
            yield match.group(1).strip('"'), body[match.end():index - 1]

    for cell_name, cell_body in blocks(text, cell_pattern):
        pins: dict[str, str] = {}
        for pin_name, pin_body in blocks(cell_body, pin_pattern):
            direction = re.search(r"\bdirection\s*:\s*(input|output|inout)\s*;",
                                  pin_body)
            if direction:
                pins[pin_name] = direction.group(1)
        area = re.search(r"\barea\s*:\s*([0-9.eE+-]+)\s*;", cell_body)
        if area:
            areas[cell_name] = float(area.group(1))
        directions[cell_name] = pins
    return directions, areas


def fanout_by_bit(module: dict, directions: dict[str, dict[str, str]]) -> Counter[int]:
    fanout: Counter[int] = Counter()
    for cell in module.get("cells", {}).values():
        cell_type = cell["type"]
        if cell_type not in directions:
            raise KeyError(f"mapped cell {cell_type} absent from Liberty")
        for port, bits in cell.get("connections", {}).items():
            if directions[cell_type].get(port) in {"input", "inout"}:
                fanout.update(bit for bit in bits if isinstance(bit, int))
    for port in module.get("ports", {}).values():
        if port["direction"] in {"output", "inout"}:
            fanout.update(bit for bit in port["bits"] if isinstance(bit, int))
    return fanout


def recursive_leaf_cells(design: dict, top: str) -> list[tuple[str, dict, tuple[str, ...]]]:
    modules = design["modules"]
    leaves: list[tuple[str, dict, tuple[str, ...]]] = []

    def walk(module_name: str, ancestry: tuple[str, ...]) -> None:
        for instance, cell in modules[module_name].get("cells", {}).items():
            cell_type = cell["type"]
            if cell_type in modules:
                walk(cell_type, ancestry + (f"{instance}:{cell_type}",))
            else:
                leaves.append((instance, cell, ancestry))

    walk(top, ())
    return leaves


def module_sha256(module: dict) -> str:
    payload = json.dumps(module, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def cell_name_type_sha256(items: list[tuple[str, str]]) -> str:
    payload = json.dumps(sorted(items), separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def common_flat_cell_identity(module: dict) -> tuple[int, str]:
    """Fingerprint the frozen common gates after hierarchy-only flattening."""
    cells = []
    for name, cell in module.get("cells", {}).items():
        # JSON backend emits ordinary hierarchical names as
        # ``u_prep.u_predictor.<cell>``.  Keep the escaped spelling too for
        # compatibility with identifiers that require Verilog escaping.
        marker = next((candidate for candidate in
                       ("u_predictor.", "\\u_predictor.")
                       if candidate in name), None)
        if marker is None:
            continue
        relative_name = name.split(marker, 1)[1]
        cells.append((relative_name, cell["type"]))
    return len(cells), cell_name_type_sha256(cells)


def classify_leaf_regions(design: dict, top: str,
                          areas: dict[str, float]) -> dict[str, dict[str, float | int]]:
    modules = design["modules"]
    counts: Counter[str] = Counter()
    region_area: defaultdict[str, float] = defaultdict(float)

    def child_region(cell_type: str, inherited: str) -> str:
        lowered = cell_type.lower()
        if "hz_predictor_roms" in lowered:
            return "common_rom"
        if "hz_predictor_csa" in lowered:
            return "common_predictor_non_rom"
        if "hz_product_v36" in lowered or "hz_product_v43" in lowered:
            return "product_specific"
        if "hz_prep" in lowered:
            return "common_candidate_selector_and_special"
        return inherited

    def walk(module_name: str, region: str) -> None:
        for cell in modules[module_name].get("cells", {}).values():
            cell_type = cell["type"]
            if cell_type in modules:
                walk(cell_type, child_region(cell_type, region))
            else:
                if cell_type not in areas:
                    raise KeyError(f"mapped cell {cell_type} has no Liberty area")
                counts[region] += 1
                region_area[region] += areas[cell_type]

    walk(top, "output_register_boundary")
    return {
        region: {"logical_cells": counts[region],
                 "logical_area_um2": region_area[region]}
        for region in sorted(counts)
    }


def first_path_details(sta: str, directions: dict[str, dict[str, str]]) -> dict:
    marker = "Startpoint:"
    if marker not in sta:
        raise ValueError("mapped STA has no timing path")
    path = marker + sta.split(marker, 1)[1]
    path = path.split("\nStartpoint:", 1)[0]
    startpoint = re.search(r"^Startpoint:\s+(.+?)\s+\(", path, re.MULTILINE)
    endpoint = re.search(r"^Endpoint:\s+(.+?)\s+\(", path, re.MULTILINE)
    if not startpoint or not endpoint:
        raise ValueError("mapped STA path has no startpoint/endpoint")

    instances: list[str] = []
    cell_types: list[str] = []
    delay_by_region: defaultdict[str, float] = defaultdict(float)
    output_pin = re.compile(r"[\^v]\s+(\S+)/(\S+)\s+\(([^)]+)\)\s*$")

    def region(instance: str) -> str:
        lowered = instance.lower()
        if "u_roms" in lowered:
            return "common_rom"
        if "u_predictor" in lowered:
            return "common_predictor_non_rom"
        if ("g_v36" in lowered or "g_v43" in lowered) and \
                ("u_pd" in lowered or "u_px" in lowered):
            return "product_specific"
        if "u_prep" in lowered:
            return "common_candidate_selector_and_special"
        return "output_register_boundary_or_unattributed"

    for line in path.splitlines():
        match = output_pin.search(line)
        if not match:
            continue
        instance, pin, cell_type = match.groups()
        if directions.get(cell_type, {}).get(pin) != "output":
            continue
        numbers = re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?",
                             line[:match.start()])
        if len(numbers) < 2:
            raise ValueError(f"cannot recover cell delay from STA row: {line}")
        delay = float(numbers[-2])
        instances.append(instance)
        cell_types.append(cell_type)
        delay_by_region[region(instance)] += delay

    return {
        "startpoint": startpoint.group(1),
        "endpoint": endpoint.group(1),
        "cell_count": len(instances),
        "buffer_count": sum("BUF" in cell_type for cell_type in cell_types),
        "logic_count": sum("BUF" not in cell_type for cell_type in cell_types),
        "instances": instances,
        "cell_types": cell_types,
        "incremental_cell_delay_by_region_ns": dict(sorted(delay_by_region.items())),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", type=int, choices=(36, 43), required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--base-metrics", type=Path, required=True)
    parser.add_argument("--common-manifest", type=Path, required=True)
    parser.add_argument("--common-verilog", type=Path, required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    out = args.directory
    mapped_json_path = out / "full_prep_v44.mapped.json"
    mapped_v_path = out / "full_prep_v44.mapped.v"
    premap_json_path = out / "premap.json"
    mapped_hier_json_path = out / "mapped.hier.json"
    final_stat = (out / "stat.rpt").read_text()
    premap_stat = (out / "premap.stat.rpt").read_text()
    sta_path = out / "mapped_sta.rpt"
    sta = sta_path.read_text()
    gate_trace_path = out / "gate-trace.txt"
    gate_trace_lines = gate_trace_path.read_text().splitlines()
    assert len(gate_trace_lines) >= 9
    assert all(line.startswith("GATE_VECTOR ") for line in gate_trace_lines)

    mapped_design = json.loads(mapped_json_path.read_text())
    premap_design = json.loads(premap_json_path.read_text())
    mapped_hier_design = json.loads(mapped_hier_json_path.read_text())
    mapped = mapped_design["modules"]["full_prep_v44"]
    base = json.loads(args.base_metrics.read_text())
    common = json.loads(args.common_manifest.read_text())

    expected_ports = {
        "Clk": ("input", 1),
        "Reset_N": ("input", 1),
        "Dividend_Hi": ("input", 64),
        "Divisor": ("input", 64),
        "NX": ("output", 96),
        "Reciprocal_Remainder": ("output", 64),
    }
    actual_ports = {
        name: (port["direction"], len(port["bits"]))
        for name, port in mapped["ports"].items()
    }
    assert actual_ports == expected_ports, actual_ports
    assert "Candidate_K" not in actual_ports
    assert not ({"Pred_S", "Pred_C", "Pred_Wrap", "Carry_Low"} & actual_ports.keys())

    cell_types = Counter(cell["type"] for cell in mapped["cells"].values())
    dffs = sum(count for kind, count in cell_types.items() if kind.startswith("DFF"))
    assert dffs == 160, dffs
    assert not mapped.get("memories")
    assert all(not module.get("memories")
               for module in premap_design["modules"].values())
    assert all(not module.get("memories")
               for module in mapped_hier_design["modules"].values())
    assert stat_value(final_stat, "Number of memories") == 0
    assert stat_value(premap_stat, "Number of memories") == 0
    assert base["top"] == "full_prep_v44"
    assert base["dff_cells"] == 160
    assert abs(base["worst_setup_slack_ns"] + base["max_data_arrival_ns"]
               - args.period) < 0.25

    directions, liberty_areas = liberty_metadata(args.liberty)
    fanout = fanout_by_bit(mapped, directions)
    rom_bits: set[int] = set()
    rom_aliases: list[str] = []
    for name, net in mapped.get("netnames", {}).items():
        if any(token in name for token in ("u_roms", "Coeff_Mem", "Square_A_Mem",
                                           "Square_B_Mem", "Cube_Mem")):
            rom_aliases.append(name)
            rom_bits.update(bit for bit in net["bits"] if isinstance(bit, int))
    rom_fanout = sorted(((fanout[bit], bit) for bit in rom_bits), reverse=True)

    path = first_path_details(sta, directions)
    path_instances = path["instances"]
    mapped_cells = mapped["cells"]
    normalized_mapped_cells = {
        normalized_instance(name): cell for name, cell in mapped_cells.items()
    }
    assert len(normalized_mapped_cells) == len(mapped_cells)
    path_sources = Counter()
    matched_instances = 0
    for instance in path_instances:
        cell = normalized_mapped_cells.get(normalized_instance(instance))
        if cell is not None:
            matched_instances += 1
            path_sources[source_file(cell)] += 1

    premap_leaves = recursive_leaf_cells(premap_design, "full_prep_v44")
    mapped_hier_leaves = recursive_leaf_cells(mapped_hier_design,
                                              "full_prep_v44")
    assert len(mapped_hier_leaves) == len(mapped["cells"]), (
        len(mapped_hier_leaves), len(mapped["cells"]))
    common_module_hashes = {
        "hz_predictor_csa": module_sha256(
            mapped_hier_design["modules"]["hz_predictor_csa"])
    }
    assert common_module_hashes["hz_predictor_csa"] == \
        common["reimport_module_json_sha256"]
    hierarchical_cost = classify_leaf_regions(mapped_hier_design,
                                               "full_prep_v44", liberty_areas)
    combined_common = hierarchical_cost.pop("common_predictor_non_rom")
    assert combined_common["logical_cells"] == common["logical_cells"]
    assert abs(combined_common["logical_area_um2"]
               - common["logical_area_um2"]) < 0.01
    hierarchical_cost["common_predictor_non_rom"] = \
        common["cost_by_region"]["predictor_non_rom"]
    hierarchical_cost["common_rom"] = common["cost_by_region"]["rom"]
    assert sum(item["logical_cells"] for item in hierarchical_cost.values()) == \
        base["logical_cells"]
    assert abs(sum(item["logical_area_um2"] for item in hierarchical_cost.values())
               - base["logical_area_um2"]) < 0.01

    premap_sources = Counter()
    for _, cell, _ in premap_leaves:
        premap_sources[source_file(cell)] += 1

    region_metrics = {}
    for region, values in hierarchical_cost.items():
        region_metrics[f"{region}_logical_cells"] = values["logical_cells"]
        region_metrics[f"{region}_logical_area_um2"] = values["logical_area_um2"]

    common_flat_count, common_flat_fingerprint = \
        common_flat_cell_identity(mapped)
    assert common_flat_count == common["logical_cells"], (
        common_flat_count, common["logical_cells"])
    assert common_flat_fingerprint == common["reimport_cell_name_type_sha256"], (
        common_flat_fingerprint, common["reimport_cell_name_type_sha256"])

    summary = dict(base)
    summary.update({
        "variant": args.variant,
        "clock_period_ns": args.period,
        "boundary_ports": actual_ports,
        "registered_output_bits": 160,
        "external_candidate_k": False,
        "final_included": False,
        "rom_representation": "Yosys-expanded combinational standard-cell logic",
        "rom_content_bits": 21248,
        "premap_generic_cells": len(premap_leaves),
        "premap_scope": "variant side with frozen common represented as a blackbox",
        "premap_memories": 0,
        "mapped_memories": 0,
        "premap_source_cell_counts": dict(sorted(premap_sources.items())),
        "mapped_source_cell_counts": cell_source_counts(mapped),
        "mapped_hierarchical_leaf_cells": len(mapped_hier_leaves),
        "mapped_hierarchical_cost_by_region": hierarchical_cost,
        "mapped_common_module_sha256": common_module_hashes,
        "common_mapped_verilog_sha256": sha256(args.common_verilog),
        "common_manifest_sha256": sha256(args.common_manifest),
        "common_source_manifest_sha256": common["source_manifest_sha256"],
        "common_production_rtl_lock_sha256":
            common["production_rtl_lock_sha256"],
        "common_reimport_module_json_sha256":
            common["reimport_module_json_sha256"],
        "common_flat_cell_count": common_flat_count,
        "common_flat_cell_name_type_sha256": common_flat_fingerprint,
        "common_dff_cells": common["dff_cells"],
        "common_boundary_ports": common["boundary_ports"],
        "rom_sha256": sha256_manifest(out / "rom-sha256.txt"),
        "mapped_tool_versions_sha256": sha256(
            out / "mapped-tool-versions.txt"),
        "gate_trace_sha256": sha256(gate_trace_path),
        "gate_vector_count": len(gate_trace_lines),
        "gate_level_functional_pass": True,
        "mapped_cell_type_counts": dict(sorted(cell_types.items())),
        "mapped_explicit_mux_cells": sum(
            count for kind, count in cell_types.items() if "MUX" in kind),
        "mapped_rom_named_net_count": len(rom_aliases),
        "mapped_rom_named_bit_count": len(rom_bits),
        "mapped_rom_named_max_direct_fanout": rom_fanout[0][0] if rom_fanout else None,
        "critical_path_instance_count": len(path_instances),
        "critical_path_instances_matched_to_json": matched_instances,
        "critical_path_source_file_counts": dict(sorted(path_sources.items())),
        "critical_path": path,
        "rom_on_first_critical_path": any(
            "u_roms" in instance.lower() for instance in path_instances),
        "rom_first_critical_path_incremental_cell_delay_ns":
            path["incremental_cell_delay_by_region_ns"].get("common_rom", 0.0),
        "mapped_netlist_sha256": sha256(mapped_v_path),
        "mapped_json_sha256": sha256(mapped_json_path),
        "liberty_sha256": sha256(args.liberty),
        "wrapper_sha256": sha256(ROOT / "full-prep" / "full_prep_top.sv"),
        "measurement": "mapped standard-cell timing without routed parasitics",
        "variant_only_mapped_verilog_sha256": sha256(
            out / "variant_only.mapped.v"),
        "mapping_mode": "single-frozen-common-plus-yosys-abc-hierarchical-default",
        "mapping_invocation": (
            f"abc -liberty <pinned Nangate45 Liberty> "
            f"-D {round(args.period * 1000)}"
        ),
        "mapping_network_policy": (
            "map the predictor/ROM once; map each variant with a predictor "
            "blackbox; overwrite it with the exact frozen real standard-cell "
            "artifact only after all ABC passes; then flatten without opt/clean"
        ),
        "common_netlist_naming_policy": common["netlist_naming_policy"],
    })
    summary.update(region_metrics)
    summary.update(time_metrics(out / "variant-yosys-time.txt", out / "yosys.log"))
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
