# V44 mathematical audit baseline: PREP correction 0..4

Date recorded: 2026-09-05

This note freezes the independently completed mathematical audit result used
for the PREP candidate tightening.  It does not introduce V45/V46 and does not
change the V44 predictor, signed cut, precision or FINAL formula.

## Exact theorem

For the unchanged V44 predictor value `p` and every divisor on the legal PREP
predictor path,

```
0 <= floor(2^96 / D) - p <= 4.
```

The exact correction range is therefore `0..4`, and both endpoints are
attained.  The five residual candidates

```
R_k = 2^96 - (p + k) D,  k = 0..4
```

are sufficient to select the exact reciprocal.  In particular,

```
2^96 - (p + 5) D < 0,
```

so candidate `p+5` can never be selected.  The exact power boundary
`D = 2^63` retains its existing dedicated bypass (`floor(2^96/D) = 2^33`)
and does not depend on candidate enumeration.

## Endpoint witnesses

The regression suite records the two audit witnesses as decimal constants so
there is no ambiguity about width or transcription.

| Role | D | p | floor(2^96/D) | Correction | Exact remainder |
| --- | ---: | ---: | ---: | ---: | ---: |
| upper endpoint | 9232379236109516801 | 8581554164 | 8581554168 | 4 | 72057585456373768 |
| lower endpoint | 9340465626629537792 | 8482249780 | 8482249780 | 0 | 7688378515850264576 |

For the upper witness, the discarded `p+5` residual is
`-9160321650653143033`.  For the lower witness it is
`-39013949617297424384`.  The model asserts these signs, the exact selected
reciprocal and remainder, and the full RTL testbenches exercise both divisors.

## What changes and what does not

The implementation change is only:

- PREP candidate generation and selection: `p..p+5` -> `p..p+4`;
- the now-unreachable helper/product case `M=5` is removed;
- the correction encoding remains three bits because value 4 is reachable.

The structural audit also found unrelated uses of the number six and left
them intact: the predictor polynomial has six coefficient/weight terms, and
V43's seven-state prefix uses a six-bit thermometer code (including its
`3'd5` state). Neither is a PREP candidate count.

The following remain bit-for-bit mathematical assumptions of V44:

- `p`, all predictor tables and direct weights;
- `t=32`, `cut=46`, `Carry_Low` and the signed-CSA reconstruction;
- the V36, V39 and V43 product formulations, including the V43 recoder;
- current FINAL correction candidates `0..3`.

A separately proved `g_L` formulation could tighten FINAL to `0..2`, but it is
only a future experiment and is not implemented here.  Combining it with this
change would destroy attribution of the PREP `6 -> 5` measurement.

The audit also confirms the existing V43 no-top-row theorem: on legal signed
predictor states, the joint radix-4 representation uses the proved 17 main
rows and needs no extra top product row.  This statement is unchanged by the
PREP correction bound.

## Evidence boundary

This theorem is the proof baseline; randomized model and RTL tests are
regressions, not its proof.  Historical synthesis and physical runs before
this tightening used six PREP candidates.  Their reports remain historical
and must not be relabeled as five-candidate results.
