# Architecture and comparison contract

## Exact operation

The current RTL implements the normalized single-limb primitive

```
{Quotient, Remainder} = (Dividend_Hi * 2^64) divmod Divisor
```

under the contract:

- `2^63 <= Divisor < 2^64`;
- `0 <= Dividend_Hi < Divisor`.

The quotient and remainder are both 64 bits. Inputs outside this contract set
`Out_Error`; normalization and a general two-limb numerator wrapper are outside
this first synthesis milestone.

## Two pipeline stages

1. `PREP` builds the exact t=32 reciprocal state and `n32 * Dividend_Hi`.
2. `FINAL` produces the exact 64-bit quotient and remainder.

All three tops have the same interface, registers, predictor ROMs, V33 direct
weights, candidate selection and FINAL logic. They differ only in the two
redundant products after the predictor cut.

| Top | Product formulation | Main reduction schedule |
| --- | --- | --- |
| `divider_v36rcm` | binary redundant cut, signed-safe | 69→63→42→28→19→13→9→6→4→3→2 |
| `divider_v39c42` | two signed radix-4 Booth recoders + wrap row | 35→28→19→13→9→6→4→3→2 |
| `divider_v43sj17` | joint radix-4, 7-state prefix, 17 rows | 17→13→9→6→4→3→2 |

The V36/V39 row counts are deliberately slightly larger than their old
unsigned analytical estimates. The V43 investigation proved that V33's
predictor carry-save rows are signed. V36 and V39 therefore retain an explicit
wrap/sign correction instead of silently reusing the invalid unsigned
assumption. V43 removes the top row only through its signed-safe proof.

## ROM treatment

The functional and full standard-cell runs include:

- 64 × 167 coefficient bits (the constant high bit of C0 is implicit);
- 256 × 16 and 32 × 10 split-square tables;
- 256 × 24 cube table.

Yosys maps these memories to standard-cell logic in the initial CI flow. This
is reproducible and identical across candidates, but it is not a physical ROM
macro model. Absolute area and timing must therefore be labelled
"standard-cell ROM mapping". A later macro-aware run may add a characterized
ROM without changing the arithmetic comparison contract.

The default mapped comparison therefore uses `kernel_v36rcm`,
`kernel_v39c42` and `kernel_v43sj17`. These tops begin at the actual signed
V33 CSA cut and end after the V34 candidate CPA/register. They include the V43
prefix and every variant-specific product/reduction level, while excluding the
common ROM, predictor multipliers and FINAL. Full divider RTL remains compiled
and simulated in every matrix job. Full standard-cell mapping is retained as a
separate control run because it is much slower and dominated by the artificial
ROM realization.

## Current implementation boundary

The PREP product trees have explicit, fixed CSA reduction depths. The common
FINAL is exact and uses the V35 parallel signed-candidate selection idea, but
its upstream products are still inferred with `*`; it is common to all three
and must not be used to claim that the original V35 unified bit heap has been
fully laid out. First CI results are engineering measurements, not a proof that
the final physical implementation has been optimized.
