#!/usr/bin/env python3
"""Generate fixed-depth row reducers used by the three product kernels."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "hz_reducers_generated.sv"


def emit_reducer(name: str, rows: int, targets: list[int]) -> str:
    lines = [
        f"module {name} #(parameter integer W = 100) (",
        f"    input wire [{rows}*W-1:0] Rows_Flat,",
        "    output wire [W-1:0] Sum,",
        "    output wire [W-1:0] Carry",
        ");",
    ]
    current = []
    for index in range(rows):
        wire = f"L0_R{index}"
        lines.append(f"    wire [W-1:0] {wire} = Rows_Flat[{index}*W +: W];")
        current.append(wire)

    for level, target in enumerate(targets, start=1):
        reductions = len(current) - target
        assert reductions >= 0 and 3 * reductions <= len(current)
        next_rows = []
        for index in range(reductions):
            sum_wire = f"L{level}_S{index}"
            carry_wire = f"L{level}_C{index}"
            a, b, c = current[3 * index : 3 * index + 3]
            lines.extend([
                f"    wire [W-1:0] {sum_wire};",
                f"    wire [W-1:0] {carry_wire};",
                f"    hz_csa3 #(.W(W)) u_l{level}_{index} (",
                f"        .A({a}), .B({b}), .C({c}),",
                f"        .Sum({sum_wire}), .Carry({carry_wire})",
                "    );",
            ])
            next_rows.extend((sum_wire, carry_wire))
        next_rows.extend(current[3 * reductions :])
        assert len(next_rows) == target
        current = next_rows

    assert len(current) == 2
    lines.extend([
        f"    assign Sum = {current[0]};",
        f"    assign Carry = {current[1]};",
        "endmodule",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    OUT.parent.mkdir(exist_ok=True)
    text = "`default_nettype none\n\n"
    text += emit_reducer("hz_reduce_69", 69, [63, 42, 28, 19, 13, 9, 6, 4, 3, 2])
    text += emit_reducer("hz_reduce_35", 35, [28, 19, 13, 9, 6, 4, 3, 2])
    text += emit_reducer("hz_reduce_17", 17, [13, 9, 6, 4, 3, 2])
    text += "`default_nettype wire\n"
    OUT.write_text(text)


if __name__ == "__main__":
    main()
