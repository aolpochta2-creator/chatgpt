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
Liberty file, and uploads the raw reports.  Full divider tops are compiled and
simulated back-to-back.  For this tightening, CI also maps the complete current
and frozen six-candidate tops in paired jobs; those full-top numbers include an
artificial standard-cell realization of the ROMs and are reported separately
from the product-kernel comparison.

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
used only for the pinned Kepler AVX-512 crash.

A calibrated sweep then rebuilt the frozen mapped V36 and V43 kernels from
placement through detailed route, OpenRCX SPEF and final STA at every period.
The 0.05 ns boundary run is
[33957430113](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33957430113).

| Kernel | Pass/fail bracket (ns) | Physical Tmin (ns) | Fmax (MHz) | Setup at Tmin (ns) | Logical area (um^2) | Routed wire (um) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 3.20 fail / 3.25 pass | 3.25 | 307.69 | +0.0086 | 71,996.358 | 699,584 |
| V43SJ17 | 3.10 fail / 3.15 pass | 3.15 | 317.46 | +0.0002 | 28,425.026 | 308,005 |

These frequencies come only from actually passing re-optimized physical
periods, not from subtracting 10 ns slack. Under this isolated typical-corner
contract V43 is 3.17% faster on the measured grid, 60.52% smaller by logical
area and 55.97% shorter by routed wire than V36 at their respective Tmin.
Thus the old fixed-period V36-timing/V43-area Pareto label does not survive the
calibrated sweep. This is not end-to-end divider or PVT signoff: V43 has only
0.2 ps setup margin at 3.15 ns, and V39 was not refined to its own Tmin.

See the [physical audit](docs/PHYSICAL_AUDIT_V44.md) for the exact contract and
caveats, [`docs/PHYSICAL_SWEEP_V44.csv`](docs/PHYSICAL_SWEEP_V44.csv) for all
29 physical job records, and
[`docs/RESULTS_V44_SYNTHESIS.md`](docs/RESULTS_V44_SYNTHESIS.md) for the
historical unbuffered checkpoint.
