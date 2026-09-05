# Exact Integer Divider R&D

[![Exact divider EDA](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/eda.yml/badge.svg)](https://github.com/aolpochta2-creator/chatgpt/actions/workflows/eda.yml)

This repository turns the V44 research checkpoint into a reproducible RTL and
open-source ASIC synthesis experiment.

## Current comparison

- **V36RCM + V34DX control**: signed-safe binary redundant-cut products.
- **V39C42 control**: separate signed radix-4 Booth products.
- **V43SJ17 candidate**: signed-safe joint radix-4 recoder with 17 main rows.
- **V44WAVE** remains a timing-bound study, not a fourth RTL candidate.

The immediate rule is unchanged: do not promote a new mathematical version
before the same compile, simulation, synthesis, mapping and STA flow has run on
V36, V39 and V43.

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
```

The GitHub Actions matrix installs Icarus Verilog and Yosys, builds a pinned
official OpenSTA, maps every comparison kernel to the same pinned Nangate45
Liberty file, and uploads the raw reports.  Full divider tops are compiled and
simulated; the mapped comparison deliberately isolates the structurally
different product kernels.

## Evidence level

The Python model currently passes 100,004 randomized/directed exact divisions.
The signed-cut, separate-Booth and joint-prefix identities pass another 200,000
randomized structural cases. These are pre-RTL mathematical checks, not a
substitute for compiled RTL simulation.

The routed physical checkpoint is complete in
[Actions run 33949336084](https://github.com/aolpochta2-creator/chatgpt/actions/runs/33949336084).
The same frozen mapped kernels were placed, clocked, routed and analyzed from
final OpenRCX SPEF at the same 10 ns constraint.

| Kernel | Logical cells | Logical area (um^2) | Max data arrival (ns) | Setup slack (ns) | Hold slack (ns) | Max-cap violations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V36RCM | 58,318 | 65,615.550 | 4.9771 | 5.1888 | 0.0556 | 1 |
| V39C42 | 41,146 | 48,677.202 | 5.3126 | 4.8358 | 0.0223 | 11 |
| V43SJ17 | 18,754 | 22,823.864 | 5.1048 | 5.0287 | 0.0236 | 1 |

At this fixed physical boundary V36 has the largest setup margin, while V43
has the smallest logical area and routed wire length. V43 is both smaller and
faster than V39 in this run. All three meet setup and hold and have zero
detailed-route DRC and antenna violations, but max-capacitance violations mean
electrical closure is incomplete. The pinned tool also required skipping its
crashing post-CTS timing-repair helper; CTS, route and final extracted STA still
ran. See the [physical audit](docs/PHYSICAL_AUDIT_V44.md) for the exact contract,
caveats and routing metrics. The historical unbuffered numbers remain in
[`docs/RESULTS_V44_SYNTHESIS.md`](docs/RESULTS_V44_SYNTHESIS.md).
