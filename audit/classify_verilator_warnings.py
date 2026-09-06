#!/usr/bin/env python3
"""Classify Verilator warnings and fail on every unreviewed relevant warning."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


STYLE_CODES = {
    "DECLFILENAME",
    "EOFNEWLINE",
    "UNUSEDSIGNAL",
    "UNUSEDPARAM",
    "UNUSEDGENVAR",
    "VARHIDDEN",
}

# Width sites accepted only when another gate checks the exact semantic intent.
# The ranges are intentionally narrow; a new warning elsewhere is unresolved.
AUDITED_WIDTH_SITES = (
    ("rtl/hz_predictor_csa.sv", range(66, 74), "intentional signed-64 polynomial arithmetic; model + elaborated wires"),
    ("rtl/hz_predictor_csa.sv", range(81, 86), "signed product widths checked from Yosys cells"),
    ("rtl/hz_prep.sv", range(110, 111), "signed4 generate constant checked for both Carry_Low values"),
    ("rtl/hz_final.sv", range(15, 16), "33x33->66 checked by microtest and Yosys"),
    ("rtl/hz_final.sv", range(18, 23), "FINAL product widths checked by microtest and Yosys"),
    ("rtl/hz_final.sv", range(39, 40), "64-bit quotient adder checked by Yosys"),
    ("rtl/hz_product_v36.sv", range(33, 35), "parameter-width modular product/shift checked structurally"),
    ("rtl/hz_product_v39.sv", range(25, 30), "signed W-bit shift/unary-minus semantics checked by microtest"),
    ("rtl/hz_product_v39.sv", range(44, 46), "parameter-width modular product/shift checked structurally"),
    ("rtl/hz_product_v43.sv", range(29, 30), "finite local-table rank conversion checked exhaustively"),
    ("rtl/hz_product_v43.sv", range(80, 83), "signed W-bit shift/unary-minus semantics checked by microtest"),
    ("rtl/hz_product_v43.sv", range(129, 131), "finite G/carry/digit behavior checked directly"),
)


@dataclass(frozen=True)
class Finding:
    level: str
    code: str
    path: str
    line: int
    text: str


HEADER = re.compile(
    r"^%(?P<level>Warning|Error)(?:-(?P<code>[A-Z0-9_]+))?:\s+"
    r"(?:(?P<path>[^:\n]+):(?P<line>\d+)(?::\d+)?:\s+)?(?P<message>.*)$"
)


def findings(path: Path) -> list[Finding]:
    result: list[Finding] = []
    current: list[str] = []
    current_match: re.Match[str] | None = None
    for line in path.read_text(errors="replace").splitlines():
        match = HEADER.match(line)
        if match:
            if current_match is not None:
                result.append(make_finding(current_match, current))
            current_match = match
            current = [line]
        elif current_match is not None:
            current.append(line)
    if current_match is not None:
        result.append(make_finding(current_match, current))
    return result


def make_finding(match: re.Match[str], lines: list[str]) -> Finding:
    return Finding(
        level=match.group("level"),
        code=match.group("code") or "ERROR",
        path=match.group("path") or "",
        line=int(match.group("line") or 0),
        text="\n".join(lines),
    )


def classify(finding: Finding) -> tuple[str, str]:
    if finding.level == "Error":
        return "unresolved-correctness", "Verilator error"
    if finding.code in STYLE_CODES:
        return "harmless/style", "non-functional naming or unused-object diagnostic"
    if finding.code in {"WIDTH", "WIDTHTRUNC", "WIDTHEXPAND"}:
        normalized = finding.path.replace("\\", "/")
        for expected_path, lines, rationale in AUDITED_WIDTH_SITES:
            if normalized.endswith(expected_path) and finding.line in lines:
                return "intentional/audited-sizing", rationale
    return "unresolved-correctness", "no committed classification/evidence for this diagnostic"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    unique: dict[tuple[str, str, str, int, str], Finding] = {}
    for log in args.logs:
        for finding in findings(log):
            key = (finding.level, finding.code, finding.path, finding.line, finding.text)
            unique[key] = finding

    rows: list[tuple[Finding, str, str]] = []
    unresolved = 0
    for finding in sorted(unique.values(), key=lambda item: (item.path, item.line, item.code)):
        category, rationale = classify(finding)
        rows.append((finding, category, rationale))
        if category == "unresolved-correctness":
            unresolved += 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as report:
        report.write("level\tcode\tpath\tline\tclassification\trationale\n")
        for finding, category, rationale in rows:
            report.write(
                f"{finding.level}\t{finding.code}\t{finding.path}\t{finding.line}\t"
                f"{category}\t{rationale}\n"
            )

    for finding, category, rationale in rows:
        print(f"{category}: {finding.code} {finding.path}:{finding.line}: {rationale}")
    if unresolved:
        raise SystemExit(f"FAIL: {unresolved} unresolved Verilator diagnostics")
    print(f"PASS Verilator warning classification: {len(rows)} unique diagnostics, 0 unresolved")


if __name__ == "__main__":
    main()
