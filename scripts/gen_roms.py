#!/usr/bin/env python3
"""Generate the three deterministic lookup tables used by the V33 front end."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def coefficients(block: int) -> tuple[int, ...]:
    m = 1025 + 16 * block
    return tuple((1 << 63) // (m ** (i + 1)) for i in range(6))


def pack_coefficients(values: tuple[int, ...]) -> int:
    c0, c1, c2, c3, c4, c5 = values
    assert c0.bit_length() == 53 and (c0 >> 52) == 1
    widths = (52, 43, 33, 23, 13, 3)
    stored = (c0 & ((1 << 52) - 1), c1, c2, c3, c4, c5)
    word = 0
    for value, width in zip(stored, widths):
        assert 0 <= value < (1 << width)
        word = (word << width) | value
    assert word < (1 << 167)
    return word


def write_hex(path: Path, values: list[int], width_bits: int) -> None:
    digits = (width_bits + 3) // 4
    path.write_text("".join(f"{value:0{digits}x}\n" for value in values))


def main() -> None:
    BUILD.mkdir(exist_ok=True)
    coeff_words = [pack_coefficients(coefficients(block)) for block in range(64)]
    square_a = [value * value for value in range(256)]
    square_b = [value * value for value in range(32)]
    cube = [value * value * value for value in range(256)]
    write_hex(BUILD / "coeff_rom.mem", coeff_words, 167)
    write_hex(BUILD / "square_a.mem", square_a, 16)
    write_hex(BUILD / "square_b.mem", square_b, 10)
    write_hex(BUILD / "cube.mem", cube, 24)


if __name__ == "__main__":
    main()
