#!/usr/bin/env python3
"""Validate and enrich one mapped full-PREP checkpoint."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stat_value(text: str, label: str) -> int:
    match = re.search(rf"{re.escape(label)}:\s+(\d+)", text)
    if not match:
        raise ValueError(f"missing {label!r} in Yosys stat")
    return int(match.group(1))


def source_file(cell: dict) -> str:
    src = str(cell.get("attributes", {}).get("src", ""))
    match = re.search(r"([^|\s]+\.sv):\d+", src)
    return match.group(1) if match else "unattributed"


def cell_source_counts(module: dict) -> dict[str, int]:
    return dict(sorted(Counter(source_file(cell) for cell in
                               module.get("cells", {}).values()).items()))


def liberty_directions(path: Path) -> dict[str, dict[str, str]]:
    text = path.read_text()
    result: dict[str, dict[str, str]] = {}
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
        result[cell_name] = pins
    return result


def fanout_by_bit(module: dict, liberty: Path) -> Counter[int]:
    directions = liberty_directions(liberty)
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


def first_path_instances(sta: str) -> list[str]:
    first = sta.split("\nStartpoint:", 1)[0]
    names = []
    for name in re.findall(r"[\^v]\s+(\S+)/\S+\s+\([A-Z][A-Z0-9_]*_X\d+\)", first):
        if name not in names:
            names.append(name)
    return names


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", type=int, choices=(36, 43), required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--base-metrics", type=Path, required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    out = args.directory
    mapped_json_path = out / "full_prep_v44.mapped.json"
    mapped_v_path = out / "full_prep_v44.mapped.v"
    premap_json_path = out / "premap.json"
    final_stat = (out / "stat.rpt").read_text()
    premap_stat = (out / "premap.stat.rpt").read_text()
    sta_path = out / "mapped_sta.rpt"
    sta = sta_path.read_text()

    mapped_design = json.loads(mapped_json_path.read_text())
    premap_design = json.loads(premap_json_path.read_text())
    mapped = mapped_design["modules"]["full_prep_v44"]
    premap = premap_design["modules"]["full_prep_v44"]
    base = json.loads(args.base_metrics.read_text())

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
    assert not premap.get("memories")
    assert stat_value(final_stat, "Number of memories") == 0
    assert stat_value(premap_stat, "Number of memories") == 0
    assert base["top"] == "full_prep_v44"
    assert base["dff_cells"] == 160
    assert abs(base["worst_setup_slack_ns"] + base["max_data_arrival_ns"]
               - args.period) < 0.25

    fanout = fanout_by_bit(mapped, args.liberty)
    rom_bits: set[int] = set()
    rom_aliases: list[str] = []
    for name, net in mapped.get("netnames", {}).items():
        if any(token in name for token in ("u_roms", "Coeff_Mem", "Square_A_Mem",
                                           "Square_B_Mem", "Cube_Mem")):
            rom_aliases.append(name)
            rom_bits.update(bit for bit in net["bits"] if isinstance(bit, int))
    rom_fanout = sorted(((fanout[bit], bit) for bit in rom_bits), reverse=True)

    path_instances = first_path_instances(sta)
    mapped_cells = mapped["cells"]
    path_sources = Counter()
    matched_instances = 0
    for instance in path_instances:
        candidates = (instance, instance.lstrip("\\"))
        cell = next((mapped_cells[name] for name in candidates if name in mapped_cells), None)
        if cell is not None:
            matched_instances += 1
            path_sources[source_file(cell)] += 1

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
        "premap_generic_cells": stat_value(premap_stat, "Number of cells"),
        "premap_memories": 0,
        "mapped_memories": 0,
        "premap_source_cell_counts": cell_source_counts(premap),
        "mapped_source_cell_counts": cell_source_counts(mapped),
        "mapped_cell_type_counts": dict(sorted(cell_types.items())),
        "mapped_explicit_mux_cells": sum(
            count for kind, count in cell_types.items() if "MUX" in kind),
        "mapped_rom_named_net_count": len(rom_aliases),
        "mapped_rom_named_bit_count": len(rom_bits),
        "mapped_rom_named_max_direct_fanout": rom_fanout[0][0] if rom_fanout else None,
        "critical_path_instance_count": len(path_instances),
        "critical_path_instances_matched_to_json": matched_instances,
        "critical_path_source_file_counts": dict(sorted(path_sources.items())),
        "mapped_netlist_sha256": sha256(mapped_v_path),
        "mapped_json_sha256": sha256(mapped_json_path),
        "liberty_sha256": sha256(args.liberty),
        "wrapper_sha256": sha256(ROOT / "full-prep" / "full_prep_top.sv"),
        "measurement": "mapped standard-cell timing without routed parasitics",
        "mapping_mode": "yosys-abc-fast",
        "mapping_invocation": (
            f"abc -fast -liberty <pinned Nangate45 Liberty> "
            f"-D {round(args.period * 1000)}"
        ),
        "mapping_network_policy": (
            "one flat full-PREP combinational network; no ROM black boxes "
            "or hierarchy cuts"
        ),
    })
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
