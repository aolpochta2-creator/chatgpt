#!/usr/bin/env python3
import random

from model.hz_model import divide, prep, prep_prediction


PREP_WITNESSES = (
    (9232379236109516801, 4),
    (9340465626629537792, 0),
)


def main() -> None:
    rng = random.Random(0x563943)
    vectors = [
        (0, 1 << 63),
        ((1 << 63) - 1, 1 << 63),
        (0, (1 << 64) - 1),
        ((1 << 64) - 2, (1 << 64) - 1),
        ((1 << 63), (1 << 63) + 1),
        ((1025 << 53) - 2, (1025 << 53) - 1),
        ((1025 << 53) - 1, 1025 << 53),
        (1025 << 53, (1025 << 53) + 1),
        ((1536 << 53) - 1, 1536 << 53),
        ((2047 << 53) - 1, 2047 << 53),
    ]
    for divisor, expected_correction in PREP_WITNESSES:
        p, correction = prep_prediction(divisor)
        reciprocal, remainder, _ = prep(divisor - 1, divisor)
        assert correction == expected_correction
        assert reciprocal == p + expected_correction
        assert remainder == (1 << 96) - reciprocal * divisor
        assert (1 << 96) - (p + 5) * divisor < 0
        vectors.append((divisor - 1, divisor))
        print(f"PREP witness D={divisor} correction={correction} p={p}")
    for _ in range(100_000):
        divisor = rng.randrange(1 << 63, 1 << 64)
        dividend_hi = rng.randrange(divisor)
        vectors.append((dividend_hi, divisor))
    for dividend_hi, divisor in vectors:
        divide(dividend_hi, divisor)
    print(f"validated {len(vectors)} exact normalized divisions; PREP range 0..4")


if __name__ == "__main__":
    main()
