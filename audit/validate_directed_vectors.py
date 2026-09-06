#!/usr/bin/env python3
"""Emit and validate the named V44 audit vectors without changing the model."""

from __future__ import annotations

import json
from pathlib import Path

from model.hz_model import divide, prep, prep_prediction


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audit-out" / "directed-vectors.json"

PREP_CASES = (
    (0, 9340465626629537792, "specified-correction-0"),
    (1, 9232379236109516799, "correction-1"),
    (2, 10377810952591741380, "correction-2"),
    (3, 9223372036854775809, "correction-3"),
    (4, 9232379236109516801, "specified-correction-4"),
)

FINAL3_D = 16960521012305199105
FINAL3_X = 16475201744807867636


def final_correction(x: int, d: int) -> int:
    _, reciprocal_remainder, product = prep(x, d)
    q0, low = divmod(product, 1 << 32)
    del q0
    rh33 = reciprocal_remainder >> 31
    vh33 = product >> 63
    g = (rh33 * vh33) >> 34
    r0_num = d * low + reciprocal_remainder * x
    assert r0_num % (1 << 32) == 0
    e = (r0_num >> 32) - g * d
    return max(k for k in range(4) if e - k * d >= 0)


def main() -> None:
    OUT.parent.mkdir(exist_ok=True)
    rows: list[dict[str, int | str]] = []

    for expected, d, label in PREP_CASES:
        p, correction = prep_prediction(d)
        assert correction == expected
        q, r = divide(d - 1, d)
        rows.append(
            {
                "label": label,
                "x": d - 1,
                "d": d,
                "p": p,
                "prep_correction": correction,
                "q": q,
                "r": r,
            }
        )

    assert final_correction(FINAL3_X, FINAL3_D) == 3
    q, r = divide(FINAL3_X, FINAL3_D)
    rows.append(
        {
            "label": "specified-final-correction-3",
            "x": FINAL3_X,
            "d": FINAL3_D,
            "final_correction": 3,
            "q": q,
            "r": r,
        }
    )

    for d, expected_m, label in (
        ((2047 << 53), 2047, "m2048-lower-edge-minus-one"),
        ((2047 << 53) + 1, 2048, "m2048-lower-edge"),
        ((1 << 64) - 1, 2048, "maximum-divisor"),
    ):
        m = ((d - 1) >> 53) + 1
        assert m == expected_m
        q, r = divide(d - 1, d)
        rows.append({"label": label, "x": d - 1, "d": d, "m": m, "q": q, "r": r})

    for x, label in ((0, "power-boundary-x0"), ((1 << 63) - 1, "power-boundary-xmax")):
        q, r = divide(x, 1 << 63)
        assert r == 0
        rows.append({"label": label, "x": x, "d": 1 << 63, "q": q, "r": r})

    OUT.write_text(json.dumps(rows, indent=2) + "\n")
    print(f"validated {len(rows)} named directed model vectors; PREP corrections 0..4; FINAL correction 3")


if __name__ == "__main__":
    main()
