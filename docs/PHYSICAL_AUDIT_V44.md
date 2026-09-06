# V44 physical audit and evidence limits

This engineering checkpoint continues the V44 family without a new arithmetic
version. It measures what physical buffering, sizing, placement and routing do
to the exact same mapped kernels used on 2026-09-04.

## Corrections to the first checkpoint

The first Yosys and OpenSTA reports are real. Their ranking applies only to the
particular mapped kernels and assumptions used in that experiment. It is not
yet a ranking of fully implemented versions from the research journal.

1. The old SDC used `set_load 0.005`. Nangate45's capacitance unit is fF, so
   this means 0.005 fF, not the 0.005 pF stated in the original report. The new
   physical flow asserts the Liberty units and uses **5 fF = 0.005 pF**.
   Because the old worst paths end at register D pins, this output-load error
   alone does not explain their ranking.
2. The old critical paths contain very heavily loaded X1 gates. The largest
   single cell arc contributes 1.8044 ns for V36 (247 loads), 1.6208 ns for V39
   (127 loads), and 1.7178 ns for V43 (127 loads). These are direct observations
   from the raw STA reports. They motivate physical buffering before choosing
   an architecture on a small difference in total delay.
3. The current V39 RTL is separate radix-4 Booth plus a fixed **3:2 row tree**.
   The journal accepts separate-Booth/Dadda as its control role, but the
   implemented reducer is neither the column-packed matrix from its proof nor
   an explicit first layer of 4:2 compressors. The module name alone does not
   establish either property.
4. V43 has its explicit seven-state joint prefix and 17 selected rows, but
   uses wide two's-complement row negation and a generic seven-level row
   reducer. It does not yet implement the compact correction-dot matrix and
   six column-Dadda stages analyzed in V43/V44. Thus this experiment neither
   validates nor disproves the V44WAVE quantitative lower bound.
5. The isolated boundary treats the 8-bit `Pred_Wrap` as an unconstrained
   primary input for V36/V39. A diagnostic sample of 50,000 legal predictor
   states found only wrap 0/1 and binary top coefficient -1/0. This is a sample,
   not a formal range proof. The generalized multipliers and paths depending
   on other wrap bits can overstate the cost of a constrained implementation.
   Cross-variant functionality is promised only on the legal predictor domain;
   the physical flow must not assume arbitrary kernel inputs are equivalent.

## Physical experiment contract

- Frozen RTL commit: `c5ad54288c14f977506c9471b88445d2bd85af1b`.
- Frozen mapped-netlist source: Actions run `33873719618` (the three
  `v*-eda-reports` artifacts). The workflow checks out current flow code but
  deliberately imports those already mapped netlists.
- Official ORFS Docker image:
  `openroad/orfs@sha256:751a77afcade9882b51427e6d9d079b8e270e7a8f4aa66df2d0659457d1c29fd`.
- Nangate45 platform is fixed at ORFS commit
  `0c914a7471340da86058dfe4d25d537f0282a508`.
- All variants use a 520 x 520 um die and a 500 x 500 um core. The absolute
  floorplan and 0.45 placement-density setting are identical. This is a
  controlled comparison, not an independently area-optimized floorplan.
- The 10 ns audit and every sweep point use input transition 0.05 ns, output
  capacitance 5 fF, zero external input/output delay, data max transition
  0.20 ns and max fanout 20. Reset is excluded from functional data timing.
  Only the requested clock period changes between jobs.
- Mapping is frozen. Constants are materialized as tie cells, then ORFS may
  buffer, size and physically implement the logic. All kernels must retain
  168 DFFs. Counts distinguish logical cells from filler/tap cells.
- Every point reruns placement, CTS, post-CTS `repair_timing`, global route,
  detailed route, OpenRCX extraction and final STA. `LEC_CHECK=0` works around
  the pinned Kepler LEC AVX-512 crash; it does not disable timing repair or
  invalidate the measured timing, geometry or extracted RC.
- Reports require detailed routing and nonempty final ODB, DEF, GDS, Verilog,
  SDC and OpenRCX SPEF files. Clock-tree insertion and hold effects are
  included in the physical reports.

Post-physical logical equivalence remains a separate open gate. Retaining 168
DFFs and producing a final netlist are useful structural checks, not an
equivalence proof.

A completed Actions job and physical closure are different statuses. A job is
successful when it produces a valid measurement even if final timing or
electrical checks fail. The strict per-point pass requires nonnegative setup
and hold slack, zero setup/hold TNS, zero detailed-route DRC and antenna
violations, and zero reported max-capacitance, max-transition and max-fanout
violations. There is no PVT sweep, characterized upstream predictor, full
PREP/FINAL timing, power analysis, or foundry signoff in this checkpoint.

## Repaired 10 ns baseline

[Actions run 33951165094](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33951165094)
at commit `fcf1e843a0dc6032a6208034e8b4d84d70250e14` is the corrected baseline.
Post-CTS `repair_timing` is enabled and observed once in every kernel's CTS
log. Only `LEC_CHECK=0` remains as the Kepler workaround.

| Kernel | Logical cells | Logical area (um^2) | Max data arrival (ns) | Setup slack (ns) | Hold slack (ns) | Max-cap | Wire (um) | Vias |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 58,318 | 65,615.550 | 4.9745 | +5.1915 | +0.0573 | 0 | 653,970 | 376,765 |
| V39C42 | 41,145 | 48,675.340 | 5.3119 | +4.8362 | +0.0240 | 12 | 658,374 | 314,069 |
| V43SJ17 | 18,754 | 22,823.864 | 5.0972 | +5.0363 | +0.0216 | 0 | 287,112 | 136,397 |

All three have setup TNS zero, max-transition and max-fanout counts zero, and
zero detailed-route DRC and antenna violations. V36 and V43 are electrically
closed; V39 remains a measured but electrically open reference.

## Calibrated period sweep

The sweep was executed as new physical implementation jobs, never as STA on a
layout produced for another period:

- coarse 6.0/5.5/5.0/4.5 ns, including V39 control: run
  [33953087457](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33953087457),
  commit `a8e3e327b5172952ddddb4c48a1eed7ba2fd669a`;
- lower coarse 4.0/3.5/3.0 ns for V36/V43: run
  [33954252869](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33954252869),
  commit `a5a9e1cf39e0e1bbc2c8ed28ceccce9460e55dbf`;
- 0.1 ns refinement 3.1 through 3.4 ns: run
  [33955844721](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33955844721),
  commit `9962ce98a0071f45883fb9221bb5082b972f6359`;
- 0.05 ns boundary confirmation: run
  [33957430113](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33957430113),
  commit `2efb847b065f96e244db3b2c5a1032564a1a57e8`.

Every run and every physical job concluded successfully as a measurement.
Every one of the 29 jobs retained 168 DFFs, invoked post-CTS
`repair_timing`, produced all six final evidence files, met hold, and had zero
max-transition, max-fanout, detailed-route DRC and antenna violations. The
complete machine-readable record, including job IDs, max data arrival,
setup/hold TNS, logical cells, buffer counts, wire, vias and evidence sizes, is
in [`PHYSICAL_SWEEP_V44.csv`](PHYSICAL_SWEEP_V44.csv). ORFS does not emit a
separate aggregate count for setup-repair buffers; the audit preserves its CTS
hold, global-route hold and route repair-design buffer counts.

The compact tables below show the fields that determine the boundary. `PASS`
means the strict definition above; `electrical` means timing/routing pass but
at least one max-capacitance violation.

| Kernel | Period (ns) | Setup (ns) | Hold (ns) | Setup TNS (ns) | Max-cap | Area (um^2) | Wire (um) | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| V36 | 6.00 | +1.2625 | +0.0292 | 0 | 0 | 65,640.288 | 658,966 | PASS |
| V36 | 5.50 | +0.8995 | +0.0251 | 0 | 1 | 65,637.894 | 655,527 | electrical |
| V36 | 5.00 | +0.4357 | +0.0488 | 0 | 0 | 65,665.026 | 662,881 | PASS |
| V36 | 4.50 | +0.1981 | +0.0251 | 0 | 0 | 65,790.578 | 694,026 | PASS |
| V36 | 4.00 | +0.1769 | +0.0228 | 0 | 0 | 66,097.808 | 700,139 | PASS |
| V36 | 3.50 | +0.0387 | +0.0312 | 0 | 0 | 68,117.280 | 714,327 | PASS |
| V36 | 3.45 | +0.0268 | +0.0246 | 0 | 1 | 69,079.934 | 718,534 | electrical |
| V36 | 3.40 | +0.0206 | +0.0430 | 0 | 1 | 69,850.004 | 719,539 | electrical |
| V36 | 3.30 | +0.0166 | +0.0502 | 0 | 1 | 71,257.410 | 723,436 | electrical |
| V36 | 3.25 | +0.0086 | +0.0500 | 0 | 0 | 71,996.358 | 699,584 | PASS |
| V36 | 3.20 | -0.0152 | +0.0242 | -0.0252 | 0 | 72,951.298 | 719,077 | setup |
| V36 | 3.10 | -0.0716 | +0.0232 | -0.4336 | 0 | 74,382.378 | 733,661 | setup |
| V36 | 3.00 | -0.1884 | +0.0373 | -2.0773 | 0 | 76,084.512 | 729,153 | setup |
| V43 | 6.00 | +1.0733 | +0.0266 | 0 | 3 | 22,812.160 | 288,977 | electrical |
| V43 | 5.50 | +0.5692 | +0.0252 | 0 | 2 | 22,808.170 | 290,496 | electrical |
| V43 | 5.00 | +0.3060 | +0.0231 | 0 | 3 | 22,847.804 | 291,652 | electrical |
| V43 | 4.50 | +0.2050 | +0.0171 | 0 | 3 | 23,034.004 | 294,327 | electrical |
| V43 | 4.00 | +0.2157 | +0.0348 | 0 | 2 | 23,163.014 | 292,405 | electrical |
| V43 | 3.50 | +0.0716 | +0.0346 | 0 | 0 | 25,231.962 | 300,394 | PASS |
| V43 | 3.40 | +0.0725 | +0.0235 | 0 | 0 | 26,214.566 | 303,231 | PASS |
| V43 | 3.30 | +0.0660 | +0.0204 | 0 | 0 | 27,221.908 | 305,578 | PASS |
| V43 | 3.20 | +0.0468 | +0.0338 | 0 | 0 | 27,944.098 | 308,406 | PASS |
| V43 | 3.15 | +0.0002 | +0.0298 | 0 | 0 | 28,425.026 | 308,005 | PASS |
| V43 | 3.10 | -0.0597 | +0.0132 | -0.3632 | 1 | 28,695.548 | 309,056 | setup + electrical |
| V43 | 3.00 | -0.1330 | +0.0270 | -1.2752 | 0 | 29,219.834 | 310,367 | setup |

V39 was intentionally kept to the requested coarse control grid:

| Kernel | Period (ns) | Setup (ns) | Hold (ns) | Max-cap | Area (um^2) | Wire (um) | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| V39 | 6.00 | +0.9057 | +0.0232 | 13 | 48,694.226 | 662,272 | electrical |
| V39 | 5.50 | +0.5084 | +0.0150 | 3 | 48,678.000 | 666,209 | electrical |
| V39 | 5.00 | +0.2325 | +0.0227 | 13 | 48,720.560 | 667,080 | electrical |
| V39 | 4.50 | +0.2165 | +0.0238 | 6 | 49,027.790 | 663,725 | electrical |

## Historical PREP6 tested-grid boundary

The value in the boundary column is the minimum strict-pass point actually
implemented on the tested historical PREP6 grid. Its corresponding grid
frequency is calculated only as `1000 / period(ns)`; no value is derived from
the 10 ns slack. These points are not a continuous optimum, a robust Fmax, or
a signoff Fmax.

| Kernel | Pass/fail bracket (ns) | Minimum strict-pass tested period (ns) | Corresponding tested-grid frequency (MHz) | Setup at boundary (ns) | Hold (ns) | Cells | Area (um^2) | Wire (um) | Vias |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 | 307.69 | +0.0086 | +0.0500 | 64,940 | 71,996.358 | 699,584 | 398,246 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 | 317.46 | +0.0002 | +0.0298 | 24,717 | 28,425.026 | 308,005 | 154,402 |

On this tested historical PREP6 grid, V43's minimum strict-pass period is 3.08%
shorter and its corresponding frequency is 3.17% higher than V36's. At those
two boundary implementations, V43 uses 60.52% less logical area, 55.97% less
routed wire and 61.23% fewer vias. At the common strict-pass point of 3.5 ns,
V43 also has more setup margin (+0.0716 versus +0.0387 ns), 62.96% less area
and 57.95% less wire.

Therefore the old fixed-10-ns Pareto label "V36=timing, V43=area/wiring" does
not survive calibrated re-optimized periods: among the two fully swept
implementations, V43 leads both physical frequency and physical size. This is
an implementation result for the isolated frozen kernels, not a declaration
that the V43 mathematics or the complete divider is universally superior.

V39 remains a reference/control. It has no electrically clean point in its
four-point coarse grid, is much larger and more heavily wired than V43, and
was not refined. Consequently no V39 physical Tmin/Fmax is claimed; its timing
potential below 4.5 ns is unmeasured, so strict Fmax domination is also not
asserted.

The boundary is discrete and not signoff-robust. V43's 3.15 ns setup margin is
only 0.2 ps. V36 shows non-monotonic one-net max-cap residuals at 3.45, 3.4 and
3.3 ns while the independently rebuilt 3.25 ns point is clean. These are valid
per-run flow outcomes, but they warn against interpolation and against
treating the 0.05 ns grid as process/voltage/temperature closure. V44WAVE
remains a timing-bound study and no V45/V46 was created.

## PREP 6 -> 5 tightening audit

This later checkpoint preserves every table above as the historical
six-candidate baseline. The independent mathematical audit proved

```
0 <= floor(2^96 / D) - p <= 4,
```

with both endpoints attained. Commit
`ee7cd589dc56ca1d3414bbd39dbe65d540cec589` removes only PREP candidate
`k=5` and the unreachable `M=5` helper choice. It does not change the
predictor, signed cut, V43 recoder, `cut=46`, `t=32` or FINAL `0..3`.
The proof baseline and exact witnesses are in
[`MATH_AUDIT_V44_PREP_TIGHTENING.md`](MATH_AUDIT_V44_PREP_TIGHTENING.md).

Successful EDA run
[33963084077](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33963084077)
maps PREP5 and frozen PREP6 kernels side by side. The PREP5 mapped areas are
62,285.496 um^2 for V36, 45,719.016 um^2 for V39 and 21,120.400 um^2 for V43,
reductions of 1.45%, 1.75% and 3.28% respectively. All retain 168 DFFs. The
complete mapped table is in
[`RESULTS_V44_SYNTHESIS.md`](RESULTS_V44_SYNTHESIS.md).

Commit `8af456f6feb5f80556d37e778cae7a98ffab7f1d` then imported those new
mapped artifacts into the unchanged physical contract. Actions run
[33963569490](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33963569490)
completed all three jobs successfully as measurements.

| Kernel | Period (ns) | Setup (ns) | Hold (ns) | Setup/hold TNS (ns) | Max-cap | Max-tran/fanout | Cells | Area (um^2) | Wire (um) | Vias | DRC/antenna | Result |
| --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |
| V36RCM | 3.25 | -0.0538 | +0.0307 | -0.1787 / 0 | 0 | 0 / 0 | 66,556 | 73,608.052 | 642,838 | 393,661 | 0 / 0 | setup fail |
| V43SJ17 | 3.20 | +0.0472 | +0.0227 | 0 / 0 | 2 | 0 / 0 | 22,444 | 26,131.840 | 294,633 | 143,788 | 0 / 0 | electrical fail |
| V43SJ17 | 3.15 | +0.0512 | +0.0150 | 0 / 0 | 1 | 0 / 0 | 22,914 | 26,604.256 | 297,279 | 145,818 | 0 / 0 | electrical fail |

Every job invoked post-CTS `repair_timing` once and produced nonempty final
ODB, DEF, GDS, Verilog, SDC and OpenRCX SPEF. The pinned ORFS variables record
`LEC_CHECK` default 0; there are no LEC artifacts, while placement/CTS/repair,
global and detailed route, extraction and final STA all ran. The exact rows
and artifact byte counts are preserved separately in
[`PHYSICAL_PREP5_V44.csv`](PHYSICAL_PREP5_V44.csv).

Compared with the old six-candidate implementations at the same periods:

| Point | Setup delta (ns) | Area delta | Wire delta | Via delta | Closure change |
| --- | ---: | ---: | ---: | ---: | --- |
| V36 @ 3.25 | -0.0624 | +1,611.694 um^2 (+2.24%) | -56,746 um (-8.11%) | -4,585 (-1.15%) | strict pass -> setup fail |
| V43 @ 3.20 | +0.0004 | -1,812.258 um^2 (-6.49%) | -13,773 um (-4.47%) | -9,144 (-5.98%) | strict pass -> 2 max-cap |
| V43 @ 3.15 | +0.0510 | -1,820.770 um^2 (-6.41%) | -10,726 um (-3.48%) | -8,584 (-5.56%) | strict pass -> 1 max-cap |

The V36 area increase despite a smaller mapped netlist is a legitimate
post-CTS/route optimization outcome, not a transcription error. Likewise, the
new V43 layouts are materially smaller but have one or two residual
max-capacitance violations. Physical optimization is discrete and cannot be
inferred monotonically from mapped cell count.

Consequently this three-point experiment establishes **no new PREP5 physical
Tmin or Fmax**. The old 3.25 ns/307.69 MHz V36 and 3.15 ns/317.46 MHz V43
values remain historical PREP6 results and must not be relabeled. Because
V43@3.15 did not remain a strict pass, the conditional 3.10 ns and 3.05 ns
runs were not launched. V39 remains the unchanged reference/control and was
not physically rerun in this narrow experiment.

The physical boundary is still the isolated `kernel_v*` path. It captures the
removal of the now-illegal `M=5` choice but not the full area of deleting one
parallel candidate branch inside complete PREP. Full-divider functional
simulation covers the actual five-branch RTL; no full-divider physical claim
is made.

## Controlled same-run PREP6/PREP5 reproducibility

The historical comparison above mixed separate source commits and separately
optimized layouts. The controlled experiment removes that ambiguity. Commit
`0ea49ea973c964ccc35f106c4cb1b7c1d89f4fd0` keeps the production PREP5 RTL
byte-for-byte unchanged and adds a build-only PREP6 control. The control is a
literal copy of the old kernel source, guarded by Git blob
`0f366d5ffea469f843e6c5d911e597f772443601`; relative to production it adds
only the `M=5` case `D + (D << 2)` / `X + (X << 2)`. It is not a V45 or a
second production architecture. A joint Icarus test checks 640 legal PREP5 vs
PREP6 cases and the restored control-only `M=5` behavior.

Both modes are mapped in one Yosys 0.33 job, retain the identical top name, and
then enter independent full physical jobs. This avoids both a source-tree
comparison and an ABC top-name perturbation. The same-run mapped inputs are:

| Kernel | PREP6 cells / area (um^2) | PREP5 cells / area (um^2) | Candidate_K direct loads | X direct loads | D direct loads | Unweighted max mapped stages to DFF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 55,697 / 63,263.844 | 54,618 / 62,285.496 | 10 -> 9 | 10,856 -> 10,483 | 8,420 -> 8,115 | 89 -> 96 |
| V43SJ17 | 17,599 / 21,837.004 | 17,106 / 21,120.400 | 11 -> 10 | 2,952 -> 2,770 | 2,510 -> 2,318 | 97 -> 97 |

The stage and direct-load counts are structural diagnostics from the mapped
JSON, not STA. They show why "fewer cells" is not equivalent to "shallower"
for V36: PREP5 reduces load and area while ABC selects a deeper Boolean DAG.
That deeper mapped DAG is consistent with the observed V36 timing degradation,
but the individual causal contributions of remapping, placement, sizing, CTS,
repair and routing were not isolated. V43 keeps its maximum structural depth
while reducing load.

Every physical job sets `GPL_RANDOM_SEED`, `GRT_SEED` and `OR_SEED` to the
matrix value. The GPL and GRT seeds are effective and the raw logs confirm
`global_placement -random_seed` and `set_global_routing_random -seed`. DRT also
receives `OR_SEED`, but `OR_K` was not set and retained its default value 0;
therefore the random-order DRT swap mechanism executed zero swaps. Detailed
routing itself still ran fully. The final layout can still change because GPL
and GRT change, so DRT receives a different routed state. All other contract
values remain frozen: Nangate45, ORFS commit/image, die/core, density, SDC
loads/transitions/fanout/reset, `SKIP_CTS_REPAIR_TIMING=0` and `LEC_CHECK=0`.

### Primary paired matrix

Actions run
[33973681605](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33973681605)
executes all six requested physical implementations from one commit and one
workflow at seed 1. All six reach final GDS, OpenRCX SPEF and final STA.

| Point | Mode | Job conclusion | Setup / TNS (ns) | Hold / TNS (ns) | Max-cap (worst fF) | Max-tran / fanout | Strict result |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| V36 @ 3.25 | PREP6 | failure* | +0.0171 / 0 | +0.0465 / 0 | 1 (-1.5242) | 0 / 1 (-2) | electrical fail |
| V36 @ 3.25 | PREP5 | success | -0.0347 / -0.0856 | +0.0292 / 0 | 0 | 0 / 0 | setup fail |
| V43 @ 3.20 | PREP6 | success | +0.0265 / 0 | +0.0194 / 0 | 0 | 0 / 0 | strict pass |
| V43 @ 3.20 | PREP5 | success | +0.0437 / 0 | +0.0222 / 0 | 2 (-2.9080) | 0 / 0 | electrical fail |
| V43 @ 3.15 | PREP6 | success | +0.0006 / 0 | +0.0187 / 0 | 0 | 0 / 0 | strict pass |
| V43 @ 3.15 | PREP5 | success | +0.0480 / 0 | +0.0156 / 0 | 1 (-2.1108) | 0 / 0 | electrical fail |

`*` The V36 PREP6 implementation is a valid measurement but its Actions job
is red. The first parser version accepted only fractional electrical slack and
rejected OpenSTA's integral `-2 (VIOLATED)` max-fanout line after the complete
flow had finished. Commit
`26494445f38875a28c76c10d7b69019cff36ee5f` fixes that reporting bug. The
fixed parser was rerun on the uploaded raw artifact to recover the row above;
the physical failure is the reported cap/fanout pair, not infrastructure.

| Point | Mode | Physical cells | Area (um^2) | Wire (um) | Vias | CTS setup/hold buffers | GRT setup/hold/repair buffers |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36 @ 3.25 | PREP6 | 68,644 | 75,422.970 | 732,397 | 410,614 | 17 / 0 | 26 / 0 / 0 |
| V36 @ 3.25 | PREP5 | 66,557 | 73,611.510 | 642,746 | 393,682 | 35 / 2 | 43 / 0 / 0 |
| V43 @ 3.20 | PREP6 | 24,445 | 28,123.648 | 307,596 | 153,938 | 21 / 6 | 27 / 0 / 0 |
| V43 @ 3.20 | PREP5 | 22,444 | 26,131.840 | 294,548 | 143,752 | 6 / 10 | 11 / 0 / 5 |
| V43 @ 3.15 | PREP6 | 24,707 | 28,334.586 | 307,877 | 154,139 | 23 / 8 | 30 / 1 / 0 |
| V43 @ 3.15 | PREP5 | 22,916 | 26,605.054 | 297,259 | 145,674 | 12 / 7 | 15 / 0 / 3 |

All rows have 168 DFFs, zero detailed-route DRC and antenna violations, one
post-CTS `repair_timing` call, and nonempty final ODB/DEF/GDS/netlist/SDC/SPEF.
The exact job IDs, artifact sizes, critical endpoints and runtime are in
[`PHYSICAL_PREP_PAIRED_V44.csv`](PHYSICAL_PREP_PAIRED_V44.csv).

The paired PREP5-PREP6 deltas from this primary matrix are:

| Point | Setup / hold delta (ns) | Arrival delta (ns) | Cells | Area | Wire | Vias | Max-cap / fanout | CTS setup/hold | GRT setup/hold/repair |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V36 @ 3.25 | -0.0518 / -0.0173 | +0.0275 | -2,087 | -1,811.460 (-2.40%) | -89,651 (-12.24%) | -16,932 (-4.12%) | -1 / -1 | +18 / +2 | +17 / 0 / 0 |
| V43 @ 3.20 | +0.0172 / +0.0028 | -0.0120 | -2,001 | -1,991.808 (-7.08%) | -13,048 (-4.24%) | -10,186 (-6.62%) | +2 / 0 | -15 / +4 | -16 / 0 / +5 |
| V43 @ 3.15 | +0.0474 / -0.0031 | -0.0463 | -1,791 | -1,729.532 (-6.10%) | -10,618 (-3.45%) | -8,465 (-5.49%) | +1 / 0 | -11 / -1 | -15 / -1 / +3 |

The timing behavior is architecture-dependent: PREP5 improves V43 setup at
both periods but worsens V36 setup. The routed size/wiring benefit is present
in all three pairs.

### Critical-cone and electrical diagnosis

The reported critical cone changes rather than merely losing one mux leaf:

| Point | PREP6 startpoint; logic/buffers/max path fanout | PREP5 startpoint; logic/buffers/max path fanout |
| --- | --- | --- |
| V36 @ 3.25 | `D[1]`; 73 / 2 / 3 | `X[2]`; 80 / 5 / 3 |
| V43 @ 3.20 | `X[0]`; 99 / 5 / 4 | `X[3]`; 94 / 4 / 4 |
| V43 @ 3.15 | `X[0]`; 98 / 6 / 3 | `X[3]`; 96 / 3 / 3 |

For V36, the PREP6 cap violation is the placed input buffer on `D[40]`; the
fanout violation is a CTS buffer driving 22 loads against the limit of 20.
Neither is the reported data critical path. For V43 PREP5 @ 3.20, the two cap
violators are routed XNOR_X1 outputs with fanout 3 and are absent from the
reported critical path. At 3.15 the sole violator is a different inserted
BUF_X1 net. Thus there is no single M=5-related net explaining the electrical
results. Removing a case arm changes ABC decomposition, placement and the
discrete set of CTS/GRT repairs globally.

### Seed reproducibility check

Because V43 @ 3.15 changed strict closure, run
[33975505349](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33975505349)
executes the predeclared PREP6/PREP5 x seed-1/seed-2 check. The run and all four
physical jobs conclude success.

| Mode | Seed | Setup / hold (ns) | Arrival (ns) | Max-cap/tran/fanout | Cells / area (um^2) | Wire / vias | CTS S/H; GRT S/H/R | Strict result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| PREP6 | 1 | +0.0006 / +0.0187 | 3.2756 | 0 / 0 / 0 | 24,707 / 28,334.586 | 307,877 / 154,139 | 23/8; 30/1/0 | pass |
| PREP5 | 1 | +0.0480 / +0.0156 | 3.2293 | 1 / 0 / 0 | 22,916 / 26,605.054 | 297,259 / 145,674 | 12/7; 15/0/3 | electrical fail |
| PREP6 | 2 | +0.0275 / +0.0193 | 3.2539 | 0 / 0 / 0 | 24,629 / 28,383.530 | 307,313 / 154,061 | 14/5; 45/2/0 | pass |
| PREP5 | 2 | +0.0547 / +0.0280 | 3.2242 | 0 / 0 / 0 | 22,896 / 26,536.160 | 295,716 / 145,641 | 5/5; 5/0/3 | pass |

Setup and hold TNS, max-transition, max-fanout, DRC and antenna are zero in
all four rows. For the two tested V43 netlists at 3.15 ns, repeating seed 1
reproduced the checked physical result in the tested environment. The
ODB/DEF/final-netlist/SDC hashes matched; SPEF differed only by its date and GDS
only by timestamps. This is a scoped reproducibility observation, not a
universal claim that the flow is deterministic at every fixed seed.

Seed 2 changes PREP6 setup by +26.9 ps and PREP5 setup by +6.7 ps. The paired
PREP5 setup advantage remains positive but ranges from +47.4 ps at seed 1 to
+27.2 ps at seed 2; its 20.2 ps spread is comparable with the PREP6 seed
scatter. PREP5 area remains 6.10-6.51% lower, wire 3.45-3.77% shorter and vias
5.46-5.49% lower. The PREP5 max-cap violation observed at seed 1 did not
reproduce at seed 2. Electrical closure is seed-sensitive in these tested
cases, but two seeds are insufficient to exclude an increased PREP5 propensity
for electrical violations.

PREP5 therefore remains the engineering baseline: it is the mathematically
minimal exact form and has a reproducible size/wiring benefit. This experiment
does **not** establish a universal timing gain or a new PREP5 Tmin/Fmax. It
does show one strict-clean PREP5 implementation at 3.15 ns (seed 2), but seed
1 is electrically non-clean and 3.10 ns was not tested. The 317.46 MHz number
must not be promoted as a new PREP5 frequency claim from a selected seed.

No immediate Tmin search is needed to decide between PREP6 and PREP5. If a new
PREP5 frequency number becomes necessary, first define whether the target is a
single best routed instance or closure across a declared seed set; only then
run a narrow boundary experiment. No `g_L`, new cut/precision, V43 restructure,
V45 or V46 was introduced here.

## Sources for the flow

- [Official ORFS Docker instructions](https://openroad-flow-scripts.readthedocs.io/en/latest/user/DockerShell.html).
- [OpenROAD resizer and repair commands](https://openroad.readthedocs.io/en/latest/main/src/rsz/README.html).
- [ORFS routed extraction and final STA source](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/0c914a7471340da86058dfe4d25d537f0282a508/flow/scripts/final_outputs.tcl).
- The attached V44 research journal and its V39/V43/V44 proof artifacts remain
  the arithmetic specification; this audit does not replace their contracts.
