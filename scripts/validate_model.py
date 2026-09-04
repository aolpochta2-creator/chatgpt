#!/usr/bin/env python3
import random

from model.hz_model import divide


def main() -> None:
    rng = random.Random(0x563943)
    vectors = [
        (0, 1 << 63),
        ((1 << 63) - 1, 1 << 63),
        (0, (1 << 64) - 1),
        ((1 << 64) - 2, (1 << 64) - 1),
    ]
    for _ in range(100_000):
        divisor = rng.randrange(1 << 63, 1 << 64)
        dividend_hi = rng.randrange(divisor)
        vectors.append((dividend_hi, divisor))
    for dividend_hi, divisor in vectors:
        divide(dividend_hi, divisor)
    print(f"validated {len(vectors)} exact normalized divisions")


if __name__ == "__main__":
    main()
