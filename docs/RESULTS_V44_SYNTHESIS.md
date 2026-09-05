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

| Kernel | Measured pass/fail bracket (ns) | Physical Tmin (ns) | Grid-defined Fmax (MHz) | Area at Tmin (um^2) | Wire at Tmin (um) |
| --- | --- | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 | 307.69 | 71,996.358 | 699,584 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 | 317.46 | 28,425.026 | 308,005 |

These are actual re-optimized routed periods, not `10 ns - slack`. On this
isolated single-corner kernel boundary V43 is 3.17% faster by the measured
grid and remains much smaller and less wired than V36. V39 was retained as a
coarse reference; it has no electrically clean point in its four tested
periods and no physical Tmin is claimed.

See the [physical audit](PHYSICAL_AUDIT_V44.md) for the exact contract,
per-point results and caveats, and
[`PHYSICAL_SWEEP_V44.csv`](PHYSICAL_SWEEP_V44.csv) for all 29 job records.
V44WAVE remains a timing-bound study. No new arithmetic version was introduced
to obtain the physical comparison.
