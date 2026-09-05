#!/usr/bin/env python3
"""Summarize one mapped netlist, including logical fanout and OpenSTA path."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path


def named_blocks(text: str, keyword: str):
    pattern = re.compile(rf"\b{re.escape(keyword)}\s*\(\s*([^\s)]+)\s*\)\s*\{{")
    for match in pattern.finditer(text):
        depth = 1
        index = match.end()
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        if depth:
            raise ValueError(f"unterminated {keyword} block {match.group(1)}")
        yield match.group(1).strip('"'), text[match.end():index - 1]


def liberty_directions(path: Path) -> dict[str, dict[str, str]]:
    directions = {}
    text = path.read_text()
    for cell_name, cell_body in named_blocks(text, "cell"):
        pins = {}
        for pin_name, pin_body in named_blocks(cell_body, "pin"):
            match = re.search(r"\bdirection\s*:\s*(input|output|inout)\s*;", pin_body)
            if match:
                pins[pin_name] = match.group(1)
        directions[cell_name] = pins
    return directions


def logical_metrics(json_path: Path, liberty_path: Path, top: str) -> dict[str, object]:
    design = json.loads(json_path.read_text())
    module = design["modules"][top]
    directions = liberty_directions(liberty_path)
    fanout = Counter()
    cell_types = Counter()

    for cell in module["cells"].values():
        cell_type = cell["type"]
        cell_types[cell_type] += 1
        if cell_type not in directions:
            raise KeyError(f"missing Liberty directions for {cell_type}")
        for port, bits in cell["connections"].items():
            if directions[cell_type].get(port) in ("input", "inout"):
                fanout.update(bit for bit in bits if isinstance(bit, int))

    # A top-level output is one additional logical sink.
    for port in module["ports"].values():
        if port["direction"] in ("output", "inout"):
            fanout.update(bit for bit in port["bits"] if isinstance(bit, int))

    aliases = {}
    for name, net in module.get("netnames", {}).items():
        for bit in net["bits"]:
            if isinstance(bit, int):
                aliases.setdefault(bit, []).append(name)

    excluded = set()
    for name in ("Clk", "Reset_N"):
        if name in module["ports"]:
            excluded.update(bit for bit in module["ports"][name]["bits"] if isinstance(bit, int))

    def max_entry(counter: Counter, excluded_bits=frozenset()):
        candidates = [(count, bit) for bit, count in counter.items() if bit not in excluded_bits]
        if not candidates:
            return 0, None, None
        count, bit = max(candidates)
        names = sorted(aliases.get(bit, []), key=lambda item: (len(item), item))
        return count, bit, names[0] if names else None

    all_count, all_bit, all_name = max_entry(fanout)
    data_count, data_bit, data_name = max_entry(fanout, excluded)
    return {
        "logical_cells": sum(cell_types.values()),
        "dff_cells": sum(count for kind, count in cell_types.items() if kind.startswith("DFF")),
        "max_logical_fanout": all_count,
        "max_logical_fanout_bit": all_bit,
        "max_logical_fanout_net": all_name,
        "max_data_fanout_excluding_clock_reset": data_count,
        "max_data_fanout_bit": data_bit,
        "max_data_fanout_net": data_name,
    }


def stat_metrics(path: Path) -> dict[str, object]:
    text = path.read_text()
    cells = re.search(r"Number of cells:\s+(\d+)", text)
    area = re.search(r"Chip area for module .*?:\s+([0-9.]+)", text)
    if not cells or not area:
        raise ValueError(f"missing cells/area in {path}")
    return {"logical_cells_from_stat": int(cells.group(1)),
            "logical_area_um2": float(area.group(1))}


def sta_metrics(path: Path) -> dict[str, object]:
    text = path.read_text()
    startpoints = re.findall(r"^Startpoint:\s+(.+?)\s*$", text, re.MULTILINE)
    endpoints = re.findall(r"^Endpoint:\s+(.+?)\s*$", text, re.MULTILINE)
    arrivals = [float(value) for value in
                re.findall(r"^\s+(-?[0-9.]+)\s+data arrival time\s*$", text, re.MULTILINE)]
    slack = re.search(r"worst slack max\s+(-?[0-9.]+)", text)
    tns = re.search(r"tns max\s+(-?[0-9.]+)", text)
    if not startpoints or not endpoints or not arrivals or not slack or not tns:
        raise ValueError(f"missing timing evidence in {path}")
    return {
        "critical_startpoint": startpoints[0],
        "critical_endpoint": endpoints[0],
        "max_data_arrival_ns": max(arrivals),
        "worst_setup_slack_ns": float(slack.group(1)),
        "setup_tns_ns": float(tns.group(1)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--stat", type=Path, required=True)
    parser.add_argument("--sta", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    summary = {"top": args.top, "label": args.label}
    summary.update(logical_metrics(args.json, args.liberty, args.top))
    summary.update(stat_metrics(args.stat))
    summary.update(sta_metrics(args.sta))
    assert summary["logical_cells"] == summary["logical_cells_from_stat"]
    args.output.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
