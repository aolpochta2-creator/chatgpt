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
- Clock period 10 ns, input transition 0.05 ns, output capacitance 5 fF, zero
  external input/output delay, data max transition 0.20 ns, max fanout 20.
  Reset is excluded from functional data timing.
- Mapping is frozen. Constants are materialized as tie cells, then ORFS may
  buffer, size and physically implement the logic. All kernels must retain
  168 DFFs. Counts distinguish logical cells from filler/tap cells.
- Reports require detailed routing and a nonempty OpenRCX SPEF read into STA.
  Clock-tree insertion and hold effects are included in the physical reports.

A completed measurement and timing closure are different statuses. The
validator requires numeric paths and reports any setup, hold or electrical
violations. A positive setup slack at this artificial block boundary is not a
full-divider Fmax. There is no PVT sweep, characterized upstream predictor,
full PREP/FINAL timing, power analysis, or foundry signoff in this checkpoint.

## Routed physical results

The first routed checkpoint completed for all three kernels in
[Actions run 33949336084](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33949336084)
at flow commit `a0a213268ff571fefc2ae830f88da8713966affc`. Each artifact contains
the final ODB, DEF, GDS, Verilog netlist, SDC and nonempty OpenRCX SPEF. Each
implemented kernel retains 168 DFFs.

The pinned OpenROAD build repeatedly crashed inside its post-CTS timing-repair
helper with `child killed: illegal instruction`. The completed run therefore
sets `SKIP_CTS_REPAIR_TIMING=1`. Clock-tree synthesis, global-route repair,
detailed routing, extraction and final STA still ran. These results are a
controlled routed audit without post-CTS timing repair.

| Kernel | Logical cells | Cells incl. fillers | Logical area (um^2) | Max data arrival (ns) | Setup slack at 10 ns (ns) | Hold slack (ns) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 58,318 | 134,001 | 65,615.550 | 4.9771 | 5.1888 | 0.0556 |
| V39C42 | 41,146 | 106,240 | 48,677.202 | 5.3126 | 4.8358 | 0.0223 |
| V43SJ17 | 18,754 | 66,824 | 22,823.864 | 5.1048 | 5.0287 | 0.0236 |

| Kernel | Routed wire (um) | Vias | Detailed-route DRC | Antenna net/pin violations | Max-cap violations |
| --- | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 653,873 | 376,623 | 0 | 0 / 0 | 1 |
| V39C42 | 658,451 | 314,336 | 0 | 0 / 0 | 11 |
| V43SJ17 | 287,235 | 136,321 | 0 | 0 / 0 | 1 |

All setup and hold checks pass at the fixed 10 ns period, and max-path TNS is
zero for every kernel. V36 has the largest setup margin. V43 is the area and
wiring leader: its logical area is 65.22% below V36 and 53.11% below V39, and
its routed wire is about 56% below both. V43 is smaller and has more setup
margin than V39 in this implementation, so the measured physical Pareto pair
is V36 for timing and V43 for area/wiring. Physical buffering and routing have
changed the historical unbuffered timing order from V39/V36/V43 to
V36/V43/V39.

Electrical closure is not complete. The remaining violations are all maximum
capacitance: V36 worst slack is -1.9009 fF at `_103411_/Z`; V39 has 11
violations with a worst slack of -7.5119 fF at `_54040_/Z`; V43 worst slack is
-1.1360 fF at `_20419_/ZN`. The validator consequently reports
`PHYSICAL_MEASUREMENT_VALID_BUT_TIMING_OR_ELECTRICAL_NOT_CLOSED`. No power or
independently optimized Fmax comparison is claimed.

## Sources for the flow

- [Official ORFS Docker instructions](https://openroad-flow-scripts.readthedocs.io/en/latest/user/DockerShell.html).
- [OpenROAD resizer and repair commands](https://openroad.readthedocs.io/en/latest/main/src/rsz/README.html).
- [ORFS routed extraction and final STA source](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/0c914a7471340da86058dfe4d25d537f0282a508/flow/scripts/final_outputs.tcl).
- The attached V44 research journal and its V39/V43/V44 proof artifacts remain
  the arithmetic specification; this audit does not replace their contracts.
