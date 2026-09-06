# V44 synthesis checkpoint

**Audit note (2026-09-05):** this historical table is preserved, but the old
output-load description was wrong: `set_load 0.005` is 0.005 fF in this Liberty.
Heavy unbuffered fanout, unrestricted wrap inputs and incomplete column packing
also limit architectural conclusions. See [the physical audit](PHYSICAL_AUDIT_V44.md)
before using this table to select a candidate.

This checkpoint is the first common mapped synthesis and static-timing
comparison of the structurally distinct V36, V39 and V43 product kernels.  It
does not introduce a new mathematical version.

## Reproducible evidence

- Source commit: `dfaf5a95767e9dcb3f9bff316eb8b350a2e8f3cc`.
- GitHub Actions run: [33872697916](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33872697916).
- All five jobs passed: exact model, three identical variant jobs, and common
  OpenSTA.
- The model checked 100,004 exact normalized divisions.  The structural model
  checked 200,000 signed-cut and V36/V39/V43 product identities.
- Each full divider was compiled with Icarus Verilog and simulated on the same
  five directed plus 25 deterministic pseudo-random vectors.
- Each variant kernel was flattened and mapped by Yosys 0.33/ABC against the
  same Nangate45 typical Liberty file pinned through OpenROAD-flow-scripts
  commit `0c914a7471340da86058dfe4d25d537f0282a508`.
- OpenSTA was built from the official source at commit
  `737b52f33b66e4c2ccc3e3ef22c3adfe9aec8d09` and applied once to all three
  mapped netlists.

## Mapped kernel results

| Kernel | Cells | Area (um^2) | Data arrival (ns) | Worst slack at 10 ns (ns) | Derived cell-only Tmin (ns) | Derived Fmax (MHz) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 55,630 | 63,203.994 | 5.6386 | 4.3221 | 5.6779 | 176.1 |
| V39C42 | 38,701 | 46,533.774 | 5.4867 | 4.4784 | 5.5216 | 181.1 |
| V43SJ17 | 17,599 | 21,837.004 | 5.9564 | 4.0077 | 5.9923 | 166.9 |

All three mapped kernels contain the same 168 `DFFR_X1` cells.  `Tmin` is
derived as `10 ns - worst slack`; it includes endpoint setup time.  The Fmax
column is only its reciprocal, not a post-route frequency claim.

## What the historical mapped measurement says

- V43 is the clear area leader: 65.45% smaller than V36 and 53.07% smaller
  than V39 in this isolated kernel comparison.
- V39 is the cell-only timing leader: its derived minimum period is 2.75%
  shorter than V36 and 7.85% shorter than V43.
- V36 is dominated by V39 at this boundary: V39 is both 26.38% smaller and
  faster.
- V39 and V43 remain the useful Pareto pair.  V43's much smaller netlist does
  not automatically make its longest path shorter; its worst path begins in a
  predictor carry input, while V39's critical path is also predictor-carry
  driven.  V36's reported worst path begins in a wrap-correction input.

## Limits of the claim

These numbers compare the variant-specific signed cut-product region, from the
V33 predictor CSA boundary through the registered V34 candidate output.  The
common ROM/predictor and FINAL logic are excluded from area and STA, although
the complete divider tops are compiled and functionally simulated.

The STA used an ideal 10 ns clock, zero external data delay, a 0.005 fF output
load, and no placement, extracted wire RC, clock-tree uncertainty, or PVT
sweep.  Reset is an explicit false path.  Therefore the ranking is a genuine
mapped cell-delay result, but not physical signoff and not an end-to-end
divider Fmax.

## Calibrated physical cross-check

The later physical flow retained these same mapped kernels and reran the
complete placement-through-extracted-STA flow at every requested period. The
coarse, 0.1 ns and 0.05 ns runs completed successfully through
[Actions run 33957430113](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33957430113).

| Kernel | Historical PREP6 bracket (ns) | Minimum strict-pass tested period (ns) | Corresponding tested-grid frequency (MHz) | Area at boundary (um^2) | Wire at boundary (um) |
| --- | --- | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 | 307.69 | 71,996.358 | 699,584 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 | 317.46 | 28,425.026 | 308,005 |

These are actual re-optimized routed periods, not `10 ns - slack`. They are
minimum strict-pass points of the tested historical PREP6 grid, not continuous
optima, robust Fmax, or signoff Fmax. On this isolated single-corner kernel
boundary V43 has a 3.17% higher corresponding frequency on the measured grid
and remains much smaller and less wired than V36. V39 was retained as a coarse
reference; it has no electrically clean point in its four tested periods and
no physical boundary frequency is claimed.

See the [physical audit](PHYSICAL_AUDIT_V44.md) for the exact contract,
per-point results and caveats, and
[`PHYSICAL_SWEEP_V44.csv`](PHYSICAL_SWEEP_V44.csv) for all 29 job records.
V44WAVE remains a timing-bound study. No new arithmetic version was introduced
to obtain the physical comparison.

## PREP 6 -> 5 paired mapped checkpoint

The later proof tightening removes only PREP candidate `k=5` and the now
unreachable `M=5` helper choice. It is still V44: predictor mathematics,
signed cut, V36/V39/V43 recoders and FINAL `0..3` are unchanged. The exact
theorem and endpoint witnesses are recorded in
[`MATH_AUDIT_V44_PREP_TIGHTENING.md`](MATH_AUDIT_V44_PREP_TIGHTENING.md).

The canonical EDA evidence is successful Actions run
[33963084077](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33963084077)
at commit `e53bb9e3e6530110715e88ad6ffd3931f9e4cb4b`. Each job mapped both that
source and frozen PREP6 commit
`fd4b23addc2e46a75d83a52f125b63656964c814` with the same Yosys 0.33/ABC
invocation and pinned Nangate45 Liberty. One OpenSTA build at commit
`737b52f33b66e4c2ccc3e3ef22c3adfe9aec8d09` then applied identical 10 ns
constraints to all six netlists.

| Kernel | PREP6 cells | PREP5 cells | Delta | PREP6 area (um^2) | PREP5 area (um^2) | Delta area | Arrival PREP6 -> PREP5 (ns) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 55,630 | 54,618 | -1,012 (-1.82%) | 63,203.994 | 62,285.496 | -918.498 (-1.45%) | 5.6540 -> 5.6934 (+0.0394) |
| V39C42 | 38,701 | 37,990 | -711 (-1.84%) | 46,533.774 | 45,719.016 | -814.758 (-1.75%) | 5.4992 -> 5.5032 (+0.0040) |
| V43SJ17 | 17,599 | 17,106 | -493 (-2.80%) | 21,837.004 | 21,120.400 | -716.604 (-3.28%) | 5.9685 -> 5.8998 (-0.0687) |

All PREP5 and PREP6 kernels contain 168 DFFs and have setup TNS zero at the
10 ns mapped checkpoint.

| Kernel | PREP5 setup slack (ns) | Critical startpoint | Critical endpoint | Maximum logical fanout | Maximum data fanout excluding clock/reset |
| --- | ---: | --- | --- | ---: | ---: |
| V36RCM | +4.2651 | `Pred_Wrap[2]` | mapped DFF `_109067_` | 312 | 312 (`Pred_C`) |
| V39C42 | +4.4607 | `Pred_C[52]` | mapped DFF `_75808_` | 192 | 192 (`Pred_Wrap`) |
| V43SJ17 | +4.0651 | `Pred_S[47]` | mapped DFF `_34040_` | 168 (`Reset_N`) | 128 (internal net) |

The mapped result is not monotonic in timing: less logic improves V43's path,
while ABC's new mapping makes V36 39.4 ps and V39 4.0 ps slower. That is why
the physical boundary was rerun instead of projecting timing from area.

This comparison boundary still accepts one `Candidate_K` and therefore sees
the removal of the unreachable `M=5` mux choice, not the full area of deleting
one parallel candidate branch inside `hz_prep`. Full divider tops were
compiled and simulated; an attempted paired full-top mapping in run
[33961763954](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33961763954)
was intentionally cancelled after the artificial standard-cell ROM expansion
remained in Yosys for about 25 minutes per candidate. This is an
infrastructure/cost boundary, not an arithmetic failure and not part of the
calibrated kernel claim.
