#!/usr/bin/env python3
"""Bit-exact checks for the signed CSA cut and all three product kernels."""

import random

from model.hz_model import coeffs, direct_weights


W = 80
MASK = (1 << W) - 1


def signed(value: int, width: int) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def csa3(a: int, b: int, c: int, wa: int = 0, wb: int = 0, wc: int = 0):
    a &= MASK
    b &= MASK
    c &= MASK
    s = a ^ b ^ c
    majority = (a & b) | (a & c) | (b & c)
    carry_out = majority >> (W - 1)
    carry = (majority << 1) & MASK
    local = (carry_out - (a >> 79) - (b >> 79) - (c >> 79)
             + (s >> 79) + (carry >> 79))
    wrap = wa + wb + wc + local
    assert signed(a, W) + signed(b, W) + signed(c, W) + (wa + wb + wc) * (1 << W) == signed(s, W) + signed(carry, W) + wrap * (1 << W)
    return s, carry, wrap


def predictor_rows(divisor: int):
    m = ((divisor - 1) >> 53) + 1
    block, d = divmod(m - 1025, 16)
    e = (m << 53) - divisor
    h1, h2, h3 = e >> 29, e >> 40, e >> 45
    weights = direct_weights(d, h1, h2 * h2, h3 * h3 * h3)
    terms = [(c * w) & MASK for c, w in zip(coeffs(block), weights)]
    s0, c0, w0 = csa3(*terms[:3])
    s1, c1, w1 = csa3(*terms[3:])
    s2, c2, w2 = csa3(s0, c0, s1, 0, w0, 0)
    return csa3(s2, c2, c1, 0, w2, w1), sum(signed(t, W) for t in terms)


def booth_digits(value: int):
    bits = value & ((1 << 34) - 1)
    sign = bits >> 33
    ext = (sign << 35) | (bits << 1)
    mapping = {0: 0, 1: 1, 2: 1, 3: 2, 4: -2, 5: -1, 6: -1, 7: 0}
    return [mapping[(ext >> (2 * i)) & 7] for i in range(17)]


def therm(rank: int) -> int:
    return (1 << rank) - 1


def local_therm(z: int) -> int:
    return therm(z if z <= 3 else z - 1)


def compose(inner: int, outer: int) -> int:
    r = [(inner >> i) & 1 for i in range(6)]
    s = [(outer >> i) & 1 for i in range(6)]
    t = [
        s[2] | s[1] * r[0] | s[0] * r[3],
        s[2] | s[1] * r[1] | s[0] * r[4],
        s[2] | s[1] * r[2] | s[0] * r[5],
        s[5] | s[4] * r[0] | s[3] * r[3],
        s[5] | s[4] * r[1] | s[3] * r[4],
        s[5] | s[4] * r[2] | s[3] * r[5],
    ]
    return sum(bit << i for i, bit in enumerate(t))


def joint_digits(u: int, v: int):
    z = [((u >> (2 * i)) & 3) + ((v >> (2 * i)) & 3) for i in range(17)]
    p = [local_therm(value) for value in z[:16]]
    for offset in (1, 2, 4, 8):
        p = [compose(p[i - offset], p[i]) if i >= offset else p[i] for i in range(16)]
    carry = [0] + [2 if p[i - 1] & 32 else 1 if p[i - 1] & 4 else 0 for i in range(1, 17)]
    digits = []
    for value, cin in zip(z, carry):
        g = value + cin
        cout = (g + 1) // 4
        digits.append(g - 4 * cout)
    return digits


def main() -> None:
    rng = random.Random(0xC5A43)
    for _ in range(200_000):
        divisor = rng.randrange((1 << 63) + 1, 1 << 64)
        (s, c, wrap), numerator = predictor_rows(divisor)
        assert numerator == signed(s, W) + signed(c, W) + wrap * (1 << W)
        carry_low = ((s & ((1 << 46) - 1)) + (c & ((1 << 46) - 1))) >> 46
        u, v = s >> 46, c >> 46
        sh, ch = signed(u, 34), signed(v, 34)
        a = sh + ch + wrap * (1 << 34)
        assert a + carry_low - 1 == (numerator >> 46) - 1

        x = rng.getrandbits(64)
        binary = (u + v + (wrap - (u >> 33) - (v >> 33)) * (1 << 34)) * x
        separate = (sum(d * (1 << (2 * i)) for i, d in enumerate(booth_digits(u)))
                    + sum(d * (1 << (2 * i)) for i, d in enumerate(booth_digits(v)))
                    + wrap * (1 << 34)) * x
        joint_value = sum(d * (1 << (2 * i)) for i, d in enumerate(joint_digits(u, v)))
        assert binary == a * x
        assert separate == a * x
        assert joint_value == a
    print("validated 200000 signed-cut and V36/V39/V43 product identities")


if __name__ == "__main__":
    main()
