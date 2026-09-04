#!/usr/bin/env python3
"""Executable integer model of the V33/V34/V35 divider data path."""

from __future__ import annotations


MASK64 = (1 << 64) - 1


def coeffs(block: int) -> tuple[int, ...]:
    m = 1025 + 16 * block
    return tuple((1 << 63) // (m ** (i + 1)) for i in range(6))


def direct_weights(d: int, h1: int, square: int, cube: int) -> tuple[int, ...]:
    s = (1 << 26, 4 * h1, square, 4 * cube)
    result = []
    for i in range(6):
        value = 0
        for j in range(min(i, 3) + 1):
            value += ((-1) ** (i + j)) * _binom(i, j) * d ** (i - j) * s[j]
        result.append(value)
    return tuple(result)


def _binom(n: int, k: int) -> int:
    if k == 0 or k == n:
        return 1
    if k == 1 or k == n - 1:
        return n
    if n == 4 and k == 2:
        return 6
    if n == 5 and k in (2, 3):
        return 10
    raise AssertionError((n, k))


def prep(dividend_hi: int, divisor: int) -> tuple[int, int, int]:
    assert 1 << 63 <= divisor < 1 << 64
    assert 0 <= dividend_hi < divisor
    if divisor == 1 << 63:
        reciprocal = 1 << 33
        return reciprocal, 0, reciprocal * dividend_hi

    m = ((divisor - 1) >> 53) + 1
    block, d = divmod(m - 1025, 16)
    e = (m << 53) - divisor
    h1 = e >> 29
    h2 = e >> 40
    h3 = e >> 45
    square = h2 * h2
    cube = h3 * h3 * h3
    weights = direct_weights(d, h1, square, cube)
    numerator = sum(c * w for c, w in zip(coeffs(block), weights))
    p = (numerator >> 46) - 1

    candidates = [(1 << 96) - (p + k) * divisor for k in range(6)]
    correction = max(k for k, residual in enumerate(candidates) if residual >= 0)
    reciprocal = p + correction
    remainder = candidates[correction]
    assert reciprocal == (1 << 96) // divisor
    assert remainder == (1 << 96) % divisor
    return reciprocal, remainder, reciprocal * dividend_hi


def divide(dividend_hi: int, divisor: int) -> tuple[int, int]:
    reciprocal, reciprocal_remainder, product = prep(dividend_hi, divisor)
    del reciprocal
    q0, low = divmod(product, 1 << 32)
    rh33 = reciprocal_remainder >> 31
    vh33 = product >> 63
    g = (rh33 * vh33) >> 34
    r0_num = divisor * low + reciprocal_remainder * dividend_hi
    assert (r0_num & ((1 << 32) - 1)) == 0
    e = (r0_num >> 32) - g * divisor
    correction = max(k for k in range(4) if e - k * divisor >= 0)
    quotient = q0 + g + correction
    remainder = e - correction * divisor
    assert quotient == (dividend_hi << 64) // divisor
    assert remainder == (dividend_hi << 64) % divisor
    assert 0 <= quotient <= MASK64 and 0 <= remainder < divisor
    return quotient, remainder
