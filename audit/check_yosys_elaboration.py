#!/usr/bin/env python3
"""Check critical widths/types in Yosys-elaborated production RTLIL."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Wire:
    name: str
    width: int
    signed: bool


@dataclass
class Cell:
    type: str
    name: str
    attrs: dict[str, str] = field(default_factory=dict)
    params: dict[str, str] = field(default_factory=dict)
    connects: dict[str, str] = field(default_factory=dict)


@dataclass
class Module:
    name: str
    wires: dict[str, Wire] = field(default_factory=dict)
    cells: list[Cell] = field(default_factory=list)


def clean(identifier: str) -> str:
    return identifier.lstrip("\\")


def parse_int(value: str) -> int:
    value = value.strip().strip('"')
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    match = re.fullmatch(r"(\d+)'([01]+)", value)
    if match:
        return int(match.group(2), 2)
    raise ValueError(f"cannot parse RTLIL integer {value!r}")


def parse_rtlil(path: Path) -> dict[str, Module]:
    modules: dict[str, Module] = {}
    module: Module | None = None
    pending_attrs: dict[str, str] = {}
    lines = path.read_text().splitlines()
    index = 0
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped.startswith("module "):
            name = stripped.split(maxsplit=1)[1]
            module = Module(name)
            modules[name] = module
            pending_attrs = {}
        elif stripped == "end" and module is not None:
            module = None
            pending_attrs = {}
        elif module is not None and stripped.startswith("attribute "):
            parts = stripped.split(maxsplit=2)
            pending_attrs[clean(parts[1])] = parts[2].strip('"') if len(parts) > 2 else ""
        elif module is not None and stripped.startswith("wire "):
            tokens = stripped.split()
            width = parse_int(tokens[tokens.index("width") + 1]) if "width" in tokens else 1
            name = tokens[-1]
            module.wires[name] = Wire(name, width, "signed" in tokens)
            pending_attrs = {}
        elif module is not None and stripped.startswith("cell "):
            tokens = stripped.split(maxsplit=2)
            cell = Cell(tokens[1], tokens[2], attrs=pending_attrs)
            pending_attrs = {}
            index += 1
            while index < len(lines):
                body = lines[index].strip()
                if body == "end":
                    break
                if body.startswith("parameter "):
                    parts = body.split(maxsplit=2)
                    cell.params[clean(parts[1])] = parts[2]
                elif body.startswith("connect "):
                    parts = body.split(maxsplit=2)
                    cell.connects[clean(parts[1])] = parts[2]
                index += 1
            module.cells.append(cell)
        index += 1
    return modules


def module_named(modules: dict[str, Module], needle: str, required_wire: str | None = None) -> Module:
    candidates = [module for name, module in modules.items() if needle in clean(name)]
    if required_wire is not None:
        candidates = [module for module in candidates if find_wire(module, required_wire, optional=True)]
    if len(candidates) != 1:
        names = ", ".join(clean(module.name) for module in candidates)
        raise AssertionError(f"expected one module containing {needle!r}, got [{names}]")
    return candidates[0]


def find_wire(module: Module, pattern: str, optional: bool = False) -> Wire | None:
    regex = re.compile(pattern)
    matches = [wire for wire in module.wires.values() if regex.fullmatch(clean(wire.name))]
    if len(matches) == 1:
        return matches[0]
    if optional and not matches:
        return None
    names = ", ".join(clean(wire.name) for wire in matches)
    raise AssertionError(
        f"{clean(module.name)}: wire pattern {pattern!r} matched {len(matches)} entries [{names}]"
    )


def check_wire(rows: list[list[str]], top: str, scope: str, module: Module,
               pattern: str, label: str, width: int, signed: bool) -> None:
    wire = find_wire(module, pattern)
    assert wire is not None
    if wire.width != width or wire.signed != signed:
        raise AssertionError(
            f"{top} {scope}.{label}: got width={wire.width} signed={wire.signed}, "
            f"expected width={width} signed={signed} ({wire.name})"
        )
    rows.append([top, scope, "wire", label, str(width), str(int(signed)), clean(wire.name)])


def source_matches(cell: Cell, filename: str, line: int) -> bool:
    haystack = " ".join([cell.name, *cell.attrs.values()])
    return re.search(rf"{re.escape(filename)}:{line}(?:\.|[^0-9])", haystack) is not None


def cell_param(cell: Cell, name: str) -> int:
    if name not in cell.params:
        raise AssertionError(f"cell {cell.name} has no parameter {name}")
    return parse_int(cell.params[name])


def check_cells(rows: list[list[str]], top: str, scope: str, module: Module,
                cell_type: str, filename: str, line: int,
                expected: tuple[int, int, int, int, int], label: str,
                minimum_count: int = 1) -> None:
    matches = [
        cell for cell in module.cells
        if clean(cell.type) == cell_type and source_matches(cell, filename, line)
    ]
    if len(matches) < minimum_count:
        raise AssertionError(
            f"{top} {scope}.{label}: found {len(matches)} {cell_type} cells at {filename}:{line}"
        )
    expected_names = ("A_WIDTH", "B_WIDTH", "Y_WIDTH", "A_SIGNED", "B_SIGNED")
    for cell in matches:
        actual = tuple(cell_param(cell, name) for name in expected_names)
        if actual != expected:
            raise AssertionError(
                f"{top} {scope}.{label}: {clean(cell.name)} params {actual}, expected {expected}"
            )
    rows.append([
        top, scope, "cell", label, str(expected[2]), str(expected[3] & expected[4]),
        f"count={len(matches)} A={expected[0]}/s{expected[3]} B={expected[1]}/s{expected[4]}",
    ])


def audit_one(path: Path, rows: list[list[str]]) -> None:
    top = path.stem.replace(".elaborated", "")
    modules = parse_rtlil(path)
    predictor = module_named(modules, "hz_predictor_csa")
    prep = module_named(modules, "hz_prep", r"g_candidate\[0\]\.M")
    final = module_named(modules, "hz_final")

    for label, width, signed in (
        ("M", 11, False), ("Bucket", 11, False),
        ("W1", 31, True), ("W2", 35, True), ("W3", 39, True),
        ("W4", 43, True), ("W5", 47, True),
        ("Product1", 75, True), ("Product2", 69, True),
        ("Product3", 63, True), ("Product4", 57, True),
        ("Product5", 51, True), ("Pred_Wrap", 8, True),
        ("Low_Add", 47, False), ("Carry_Low", 1, False),
    ):
        check_wire(rows, top, "predictor", predictor, re.escape(label), label, width, signed)

    for pattern, label, width, signed in (
        (r"g_candidate\[0\]\.M", "candidate[0].M", 4, True),
        (r"g_candidate\[0\]\.MD", "multiple68 result", 68, False),
        (r"g_candidate\[0\]\.MX", "multiple100 result", 100, False),
        (r"Residual_Candidate\[0\]", "Residual_Candidate[0]", 68, False),
        (r"NX_Candidate\[0\]", "NX_Candidate[0]", 100, False),
        (r"Correction", "Correction", 3, False),
        (r"Selected_Residual", "Selected_Residual", 68, False),
        (r"Selected_NX", "Selected_NX", 100, False),
    ):
        check_wire(rows, top, "PREP", prep, pattern, label, width, signed)

    for label, width, signed in (
        ("G_Product", 66, False), ("DL", 96, False), ("RX", 128, False),
        ("R0_Numerator", 129, False), ("GD", 96, False), ("E", 98, True),
        ("R0_Candidate", 98, True), ("R1_Candidate", 98, True),
        ("R2_Candidate", 98, True), ("R3_Candidate", 98, True),
        ("Correction", 2, False), ("Quotient", 64, False),
    ):
        check_wire(rows, top, "FINAL", final, re.escape(label), label, width, signed)

    check_cells(rows, top, "predictor", predictor, "$mul", "hz_predictor_csa.sv", 81,
                (44, 31, 75, 1, 1), "Product1 44s*31s->75s")
    check_cells(rows, top, "predictor", predictor, "$mul", "hz_predictor_csa.sv", 82,
                (34, 35, 69, 1, 1), "Product2 34s*35s->69s")
    check_cells(rows, top, "predictor", predictor, "$mul", "hz_predictor_csa.sv", 83,
                (24, 39, 63, 1, 1), "Product3 24s*39s->63s")
    check_cells(rows, top, "predictor", predictor, "$mul", "hz_predictor_csa.sv", 84,
                (14, 43, 57, 1, 1), "Product4 14s*43s->57s")
    check_cells(rows, top, "predictor", predictor, "$mul", "hz_predictor_csa.sv", 85,
                (4, 47, 51, 1, 1), "Product5 4s*47s->51s")

    check_cells(rows, top, "FINAL", final, "$mul", "hz_final.sv", 15,
                (33, 33, 66, 0, 0), "G_Product 33u*33u->66u")
    check_cells(rows, top, "FINAL", final, "$mul", "hz_final.sv", 18,
                (64, 32, 96, 0, 0), "DL 64u*32u->96u")
    check_cells(rows, top, "FINAL", final, "$mul", "hz_final.sv", 19,
                (64, 64, 128, 0, 0), "RX 64u*64u->128u")
    check_cells(rows, top, "FINAL", final, "$mul", "hz_final.sv", 22,
                (32, 64, 96, 0, 0), "GD 32u*64u->96u")
    check_cells(rows, top, "FINAL", final, "$add", "hz_final.sv", 39,
                (64, 64, 64, 0, 0), "quotient adders 64u+64u->64u", minimum_count=2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("rtlil", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    rows: list[list[str]] = []
    for path in args.rtlil:
        audit_one(path, rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as report:
        report.write("top\tscope\tkind\tnode\twidth\tsigned\tevidence\n")
        for row in rows:
            report.write("\t".join(row) + "\n")
    print(f"PASS Yosys elaboration: {len(rows)} critical width/type checks")


if __name__ == "__main__":
    main()
