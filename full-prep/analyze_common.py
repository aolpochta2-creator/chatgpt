#!/usr/bin/env python3
"""Validate and record the one-time mapped full-PREP predictor/ROM block."""

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


def module_sha(module: dict) -> str:
    payload = json.dumps(module, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def cell_name_type_sha(module: dict) -> str:
    payload = json.dumps(sorted(
        (name, cell["type"]) for name, cell in module.get("cells", {}).items()
    ), separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def named_blocks(text: str, keyword: str):
    pattern = re.compile(rf"\b{re.escape(keyword)}\s*\(\s*([^\s)]+)\s*\)\s*\{{")
    for match in pattern.finditer(text):
        depth = 1
        index = match.end()
        while index < len(text) and depth:
            depth += (text[index] == "{") - (text[index] == "}")
            index += 1
        if depth:
            raise ValueError(f"unterminated {keyword} block {match.group(1)}")
        yield match.group(1).strip('"'), text[match.end():index - 1]


def liberty_areas(path: Path) -> dict[str, float]:
    result = {}
    for name, body in named_blocks(path.read_text(), "cell"):
        match = re.search(r"\barea\s*:\s*([0-9.eE+-]+)\s*;", body)
        if match:
            result[name] = float(match.group(1))
    return result


def recursive_cost(design: dict, top: str, areas: dict[str, float]) -> dict:
    modules = design["modules"]
    counts: Counter[str] = Counter()
    costs: defaultdict[str, float] = defaultdict(float)

    def walk(module_name: str, region: str) -> None:
        for cell in modules[module_name].get("cells", {}).values():
            kind = cell["type"]
            next_region = "rom" if kind == "hz_predictor_roms" else region
            if kind in modules:
                walk(kind, next_region)
            else:
                if kind not in areas:
                    raise KeyError(f"mapped common cell {kind} absent from Liberty")
                counts[next_region] += 1
                costs[next_region] += areas[kind]

    walk(top, "predictor_non_rom")
    return {
        region: {
            "logical_cells": counts[region],
            "logical_area_um2": costs[region],
        }
        for region in sorted(counts)
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--liberty", type=Path, required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    out = args.directory
    top = "hz_predictor_csa"
    mapped_v = out / "common_predictor.mapped.v"
    mapped_json = out / "common_predictor.mapped.json"
    reimport_json = out / "common_predictor.reimport.json"
    hierarchical_json = out / "common_predictor.mapped.hier.json"
    premap_json = out / "common_predictor.premap.json"
    design = json.loads(mapped_json.read_text())
    reimport = json.loads(reimport_json.read_text())
    hierarchical = json.loads(hierarchical_json.read_text())
    premap = json.loads(premap_json.read_text())
    module = design["modules"][top]
    reimport_module = reimport["modules"][top]

    expected_ports = {
        "Divisor": ("input", 64),
        "Pred_S": ("output", 80),
        "Pred_C": ("output", 80),
        "Pred_Wrap": ("output", 8),
        "Carry_Low": ("output", 1),
        "Is_Power_Boundary": ("output", 1),
    }
    ports = {name: (port["direction"], len(port["bits"]))
             for name, port in module["ports"].items()}
    assert ports == expected_ports, ports
    assert {name: (port["direction"], len(port["bits"]))
            for name, port in reimport_module["ports"].items()} == expected_ports
    assert not module.get("memories")
    assert all(not item.get("memories") for item in premap["modules"].values())
    assert all(not item.get("memories")
               for item in hierarchical["modules"].values())

    areas = liberty_areas(args.liberty)
    cells = Counter(cell["type"] for cell in module.get("cells", {}).values())
    logical_area = sum(areas[kind] * count for kind, count in cells.items())
    dffs = sum(count for kind, count in cells.items() if kind.startswith("DFF"))
    assert dffs == 0
    regions = recursive_cost(hierarchical, top, areas)
    assert set(regions) == {"predictor_non_rom", "rom"}, regions
    assert sum(item["logical_cells"] for item in regions.values()) == sum(cells.values())
    assert abs(sum(item["logical_area_um2"] for item in regions.values())
               - logical_area) < 0.01

    source_files = (ROOT / "full-prep" / "common-source-sha256.txt").read_text()
    rom_hashes = {}
    for line in (out / "rom-sha256.txt").read_text().splitlines():
        digest, path = line.split(maxsplit=1)
        rom_hashes[path] = digest

    # Re-imported JSON comes from the emitted mapped Verilog.  Its module hash
    # is the canonical structural identity checked after both compositions.
    summary = {
        "top": top,
        "boundary": (
            "real bucket/ROM/polynomial/signed-CSA predictor through Pred_S, "
            "Pred_C, Pred_Wrap, Carry_Low and Is_Power_Boundary"
        ),
        "boundary_ports": ports,
        "clock_period_ns": args.period,
        "abc_delay_ps": round(args.period * 1000),
        "mapping_mode": "single-build-yosys-abc-hierarchical-default",
        "mapping_invocation": (
            f"abc -liberty <pinned Nangate45 Liberty> "
            f"-D {round(args.period * 1000)}"
        ),
        "logical_cells": sum(cells.values()),
        "logical_area_um2": logical_area,
        "dff_cells": dffs,
        "memories": 0,
        "cell_type_counts": dict(sorted(cells.items())),
        "cost_by_region": regions,
        "rom_content_bits": 21248,
        "rom_representation": (
            "generated ROM arrays expanded and mapped once into real "
            "Nangate45 standard-cell combinational logic"
        ),
        "rom_sha256": rom_hashes,
        "source_file_sha256_manifest": source_files.splitlines(),
        "source_manifest_sha256": sha256(
            ROOT / "full-prep" / "common-source-sha256.txt"),
        "production_rtl_lock_sha256": sha256(
            ROOT / "audit" / "production_rtl_v44_prep5.sha256"),
        "liberty_sha256": sha256(args.liberty),
        "mapped_verilog_sha256": sha256(mapped_v),
        "mapped_json_sha256": sha256(mapped_json),
        "mapped_module_json_sha256": module_sha(module),
        "reimport_json_sha256": sha256(reimport_json),
        "reimport_module_json_sha256": module_sha(reimport_module),
        "reimport_cell_name_type_sha256": cell_name_type_sha(reimport_module),
        "yosys_time_sha256": sha256(out / "common-yosys-time.txt"),
        "mapped_tool_versions_sha256": sha256(out / "mapped-tool-versions.txt"),
        "abc_runtime_and_peak_memory": "recorded in common-yosys-time.txt and yosys.log",
        "mapping_scope": "one invocation in one common_mapped Actions job",
        "blackbox_or_oracle": False,
    }
    args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
