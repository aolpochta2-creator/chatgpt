# Exact Integer Divider R&D

[![Exact divider EDA](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/eda.yml/badge.svg)](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/eda.yml)
[![V44 physical kernel audit](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/physical.yml/badge.svg)](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/physical.yml)

This repository turns the V44 research checkpoint into a reproducible RTL and
open-source ASIC synthesis experiment.

## Current comparison

- **V36RCM + V34DX control**: signed-safe binary redundant-cut products.
- **V39C42 control**: separate signed radix-4 Booth products.
- **V43SJ17 candidate**: signed-safe joint radix-4 recoder with 17 main rows.
- **V44WAVE** remains a timing-bound study, not a fourth RTL candidate.

Architectural claims remain tied to common evidence: do not promote a new
mathematical version without the same compile, simulation, synthesis, mapping
and physical timing flow on the relevant controls. The V44 calibrated physical
sweep below adds no V45/V46 and changes no divider mathematics.

The current proof baseline tightens only PREP from six candidates `p..p+5` to
the exact five-candidate range `p..p+4`:

```
0 <= floor(2^96 / D) - p <= 4
```

Both endpoints are attained and `p+5` is never selected.  Predictor
mathematics, `t=32`, `cut=46`, signed-cut logic and the current FINAL range
`0..3` are unchanged.  The proved future `g_L`/FINAL `0..2` experiment is not
implemented.  See the
[mathematical audit baseline](docs/MATH_AUDIT_V44_PREP_TIGHTENING.md).

## Implemented operation

The first milestone is the exact normalized primitive

```
{Quotient, Remainder} = (Dividend_Hi * 2^64) divmod Divisor
```

with `Divisor[63] = 1` and `Dividend_Hi < Divisor`. It is framed as two
pipeline stages and accepts one input per cycle. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the comparison contract,
signed-CSA correction and present implementation boundary.

## Reproduce

```bash
make model
make structure
make test TESTS=5000

# For mapped runs:
export LIBERTY=/path/to/NangateOpenCellLibrary_typical.lib
make synth-v36
make synth-v39
make synth-v43

# Optional paired full-divider mapping (standard-cell ROM realization):
make synth-full-v36
make synth-full-v39
make synth-full-v43
```

The GitHub Actions matrix installs Icarus Verilog and Yosys, builds a pinned
official OpenSTA, maps every comparison kernel to the same pinned Nangate45
Liberty file, and uploads paired current/frozen-six-candidate reports.  Full
divider tops are compiled and simulated back-to-back.  Full-top mapping remains
an optional local control because its artificial standard-cell ROM realization
is prohibitively expensive and is not the calibrated comparison boundary.

## Evidence level

The Python model currently passes 100,012 randomized/directed exact divisions,
including explicit PREP correction-0 and correction-4 witnesses.
The signed-cut, separate-Booth and joint-prefix identities pass another 200,000
randomized structural cases. These are pre-RTL mathematical checks, not a
substitute for compiled RTL simulation.

The physical values below are the preserved **six-candidate historical
baseline**, not results of the current tightening.  The corrected 10 ns run is
[Actions run 33951165094](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33951165094).
V36 and V43 have full reported electrical closure there; V39 remains the
12-max-cap reference. Post-CTS `repair_timing` is enabled. `LEC_CHECK=0` is
used only for the pinned Kepler AVX-512 crash: it does not disable timing
repair or invalidate timing/geometry/RC measurements. Post-physical logical
equivalence remains an open gate; 168 DFFs and a final netlist are not an
equivalence proof.

A calibrated sweep then rebuilt the frozen mapped V36 and V43 kernels from
placement through detailed route, OpenRCX SPEF and final STA at every period.
The 0.05 ns boundary run is
[33957430113](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33957430113).

| Kernel | Historical PREP6 bracket (ns) | Minimum strict-pass tested period (ns) | Corresponding tested-grid frequency (MHz) | Setup at boundary (ns) | Logical area (um^2) | Routed wire (um) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 | 307.69 | +0.0086 | 71,996.358 | 699,584 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 | 317.46 | +0.0002 | 28,425.026 | 308,005 |

These frequencies come only from actually passing re-optimized physical
periods, not from subtracting 10 ns slack. They are minimum strict-pass points
of the tested historical PREP6 grid, not continuous optima, robust Fmax, or
signoff Fmax. Under this isolated typical-corner contract V43 has a 3.17%
higher corresponding frequency on the measured grid, 60.52% less logical area
and 55.97% less routed wire than V36 at their respective boundary points.
Thus the old fixed-period V36-timing/V43-area Pareto label does not survive the
calibrated sweep. This is not end-to-end divider or PVT signoff: V43 has only
0.2 ps setup margin at 3.15 ns, and V39 was not refined to its own boundary.

Those values are intentionally retained as PREP6 history. The five-candidate
RTL was validated and mapped in successful EDA run
[33963084077](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33963084077),
then physically rebuilt only at V36 3.25 ns and V43 3.20/3.15 ns in run
[33963569490](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33963569490).
V36@3.25 missed setup by 0.0538 ns. V43 met setup/hold at both periods and used
6.4-6.5% less routed logical area than the old layouts, but retained two and
one max-cap violations respectively. Therefore none is a strict PREP5 pass and
no new Tmin/Fmax is claimed. The conditional V43 3.10/3.05 ns runs were not
started.

A later paired check rebuilt PREP6 and PREP5 from one source tree, workflow and
declared seed in [run 33973681605](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33973681605),
then repeated V43 at seeds 1/2 in successful
[run 33975505349](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33975505349).
PREP5 keeps a stable V43 area reduction of 6.10-6.51% and wire reduction of
3.45-3.77%; its setup advantage is +47.4 ps at seed 1 and +27.2 ps at seed 2.
The seed-1 max-cap residual does not reproduce at seed 2, which is strict
clean. This establishes seed-sensitive closure in the tested cases, but two
seeds cannot exclude an increased PREP5 propensity for electrical violations.
The GPL and GRT seeds were effective; DRT received `OR_SEED`, but `OR_K=0`
meant zero random-order swaps. Full detailed routing still ran, and its input
state could change with GPL/GRT. PREP5 therefore remains the engineering
baseline, but no new PREP5 Tmin/Fmax is claimed.

See the [physical audit](docs/PHYSICAL_AUDIT_V44.md) for the exact contract and
caveats, [`docs/PHYSICAL_SWEEP_V44.csv`](docs/PHYSICAL_SWEEP_V44.csv) for all
29 historical PREP6 job records,
[`docs/PHYSICAL_PREP5_V44.csv`](docs/PHYSICAL_PREP5_V44.csv) for the three
PREP5 measurements,
[`docs/PHYSICAL_PREP_PAIRED_V44.csv`](docs/PHYSICAL_PREP_PAIRED_V44.csv) for
the controlled same-run and seed-check evidence, and
[`docs/RESULTS_V44_SYNTHESIS.md`](docs/RESULTS_V44_SYNTHESIS.md) for the
historical and paired mapped checkpoints.
